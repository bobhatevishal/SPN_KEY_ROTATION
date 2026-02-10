#!/bin/bash

set -euo pipefail

# === Load environment from db_env.sh ===
: "${DB_ENV_FILE:=./db_env.sh}"

if [ ! -f "${DB_ENV_FILE}" ]; then
  echo "db_env.sh not found at ${DB_ENV_FILE}" >&2
  exit 1
fi

# shellcheck source=./db_env.sh
source "${DB_ENV_FILE}"

# Validate required variables
: "${AZURE_TENANT_ID:?db_env.sh must export AZURE_TENANT_ID}"
: "${KEYVAULT_NAME:?db_env.sh must export KEYVAULT_NAME}"
: "${CONN_DISPLAY_NAME:=db-automation-spn}"
: "${ID_NAME:=db-automation-spn-id}"
: "${SECRET_NAME:=db-automation-spn-secret}"
: "${FABRIC_API_BASE:=https://api.fabric.microsoft.com/v1}"

log() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"
}

err() {
  log "ERROR! $*" >&2
  exit 1
}

# --- 1. Get Bearer token for Fabric via Azure CLI ---
log "Acquiring Fabric API Token using current Azure identity..."

# Leverages the existing 'az login' or Managed Identity session
FABRIC_TOKEN=$(az account get-access-token \
    --resource "https://api.fabric.microsoft.com/" \
    --query accessToken -o tsv)

if [ -z "$FABRIC_TOKEN" ] || [ "$FABRIC_TOKEN" = "null" ]; then
  err "Failed to acquire Fabric token. Ensure 'az login' or Managed Identity is active."
fi

log "Successfully obtained Fabric Bearer token"

# --- 2. Fetch target credentials from Key Vault ---
log "Fetching target SPN secrets from Key Vault '${KEYVAULT_NAME}'"

CLIENT_ID=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name "$ID_NAME" --query "value" -o tsv)
CLIENT_SECRET=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name "$SECRET_NAME" --query "value" -o tsv)

if [ -z "$CLIENT_ID" ] || [ -z "$CLIENT_SECRET" ]; then
  err "Target Client ID or Secret not found in Key Vault"
fi

# --- 3. Find Fabric connection by displayName ---
list_conn_response=$(curl -s \
  -H "Authorization: Bearer ${FABRIC_TOKEN}" \
  "${FABRIC_API_BASE}/connections")

TARGET_ID=$(echo "$list_conn_response" | jq -r \
  --arg name "$CONN_DISPLAY_NAME" \
  '.value[] | select(.displayName==$name) | .id')

if [ -z "$TARGET_ID" ] || [ "$TARGET_ID" = "null" ]; then
  err "Connection '${CONN_DISPLAY_NAME}' not found in Fabric"
fi

CONN_TYPE=$(echo "$list_conn_response" | jq -r --arg id "$TARGET_ID" '.value[] | select(.id==$id) | .connectivityType')

# --- 4. Build the Payload (Basic/Extension Schema) ---
log "Constructing payload for Basic/Extension type..."

# Extension/Power Query types require credentials to be a stringified JSON object
INNER_CREDS=$(jq -nc \
  --arg user "$CLIENT_ID" \
  --arg pass "$CLIENT_SECRET" \
  '{"credentialData": [{"name": "username", "value": $user}, {"name": "password", "value": $pass}]}')

PAYLOAD=$(jq -n \
  --arg name "$CONN_DISPLAY_NAME" \
  --arg connType "$CONN_TYPE" \
  --arg creds "$INNER_CREDS" \
  '{
    connectionDetails: {
      host: "adb-7405609173671370.10.azuredatabricks.net",
      httpPath: "/sql/1.0/warehouses/559747c78f71249c"
    },
    connectivityType: $connType,
    gatewayType: "TenantCloud",
    displayName: $name,
    credentialDetails: {
      credentialType: "Basic",
      credentials: $creds,
      encryptedConnection: "Any",
      encryptionAlgorithm: "NONE",
      privacyLevel: "Organizational",
      useCallerCredentials: false
    }
  }' | jq -c)

# --- 5. PATCH Fabric connection ---
log "Updating Fabric connection..."

HTTP_RESPONSE=$(curl -s -w "%{http_code}" \
  -X PATCH \
  -H "Authorization: Bearer ${FABRIC_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "${PAYLOAD}" \
  "${FABRIC_API_BASE}/connections/${TARGET_ID}" \
  -o /tmp/fabric_resp.json)

if [[ "$HTTP_RESPONSE" != "200" && "$HTTP_RESPONSE" != "204" ]]; then
  resp=$(cat /tmp/fabric_resp.json)
  log "Fabric API returned HTTP $HTTP_RESPONSE"
  log "Response body: $resp"
  err "Failed to update Fabric connection"
fi

log "-------------------------------------------------------"
log " SUCCESS: Fabric connection rotated successfully."
log " Connection ID: ${TARGET_ID}"
log "-------------------------------------------------------"
