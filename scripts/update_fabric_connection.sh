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
: "${FABRIC_AUTH_CLIENT_ID:?db_env.sh must export FABRIC_AUTH_CLIENT_ID}"
: "${FABRIC_AUTH_CLIENT_SECRET:?db_env.sh must export FABRIC_AUTH_CLIENT_SECRET}"
: "${CONN_DISPLAY_NAME:=db-automation-spn}"
: "${KID_CLIENT_ID:=db-automation-spn-id}"
: "${KID_CLIENT_SECRET:=db-automation-spn-secret}"
: "${FABRIC_API_BASE:=https://api.fabric.microsoft.com/v1}"

log() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"
}

err() {
  log "ERROR! $*" >&2
  exit 1
}

# --- 1. Get Bearer token for Fabric (SPN) ---
log "Requesting Fabric Bearer token..."

TOKEN_RESPONSE=$(curl -s -X POST \
  "https://login.microsoftonline.com/${AZURE_TENANT_ID}/oauth2/v2.0/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" \
  -d "client_id=${FABRIC_AUTH_CLIENT_ID}" \
  -d "client_secret=${FABRIC_AUTH_CLIENT_SECRET}" \
  -d "scope=https://api.fabric.microsoft.com/.default" \
)

FABRIC_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')

if [ -z "$FABRIC_TOKEN" ] || [ "$FABRIC_TOKEN" = "null" ]; then
  log "Raw token response: $TOKEN_RESPONSE"
  err "Failed to get Fabric Bearer token"
fi

log "Successfully obtained Fabric Bearer token"

# --- 2. Fetch credentials from Key Vault ---
log "Fetching secrets from Key Vault '${KEYVAULT_NAME}'"

CLIENT_ID=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name "$KID_CLIENT_ID" --query "value" -o tsv)
CLIENT_SECRET=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name "$KID_CLIENT_SECRET" --query "value" -o tsv)

if [ -z "$CLIENT_ID" ] || [ -z "$CLIENT_SECRET" ]; then
  err "Key Vault secrets are empty or missing"
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

log "Found Fabric connection: id=${TARGET_ID}, type=${CONN_TYPE}"

# --- 4. Build the Payload (The Out-of-the-box Fix) ---
# Your dump showed 'Basic' type with stringified 'credentialData'
log "Constructing Basic/Extension payload..."

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
log "PATCHing Fabric connection at ${FABRIC_API_BASE}/connections/${TARGET_ID}"

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
  err "Failed to update Fabric connection credentials"
fi

log "-------------------------------------------------------"
log " SUCCESS: Fabric connection rotated successfully"
log " Connection ID: ${TARGET_ID}"
log "-------------------------------------------------------"
