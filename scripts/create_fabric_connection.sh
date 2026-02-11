#!/bin/bash
set -euo pipefail

# === 1. Setup & Token ===
log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }
err() { log "ERROR: $*" >&2; exit 1; }

# Load variables from your db_env.sh
source ./db_env.sh

log "Acquiring Fabric Token via Azure CLI..."
FABRIC_TOKEN=$(az account get-access-token --resource "https://api.fabric.microsoft.com/" --query accessToken -o tsv)

# === 2. Fetch Secrets from Key Vault ===
log "Fetching Databricks secrets from ${KEYVAULT_NAME}..."
CLIENT_ID=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name "$ID_NAME" --query "value" -o tsv)
CLIENT_SECRET=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name "$SECRET_NAME" --query "value" -o tsv)

# === 3. Construct Payload ===
# We MUST include connectionDetails for Databricks to avoid 400 Bad Request
INNER_CREDS=$(jq -n --arg user "$CLIENT_ID" --arg pass "$CLIENT_SECRET" \
  '{"credentialData": [{"name": "username", "value": $user}, {"name": "password", "value": $pass}]}')

PAYLOAD=$(jq -n --arg name "$TARGET_SPN_DISPLAY_NAME" --argjson creds "$INNER_CREDS" \
  '{
    displayName: $name,
    connectivityType: "Shareable",
    gatewayType: "TenantCloud",
    connectionDetails: {
      host: "adb-7405609173671370.10.azuredatabricks.net",
      httpPath: "/sql/1.0/warehouses/559747c78f71249c"
    },
    credentialDetails: {
      credentialType: "Basic",
      credentials: $creds,
      encryptedConnection: "Any",
      encryptionAlgorithm: "NONE",
      privacyLevel: "Organizational",
      useCallerCredentials: false
    }
  }' | jq -c)

# === 4. Execute Create (POST) ===
log "Creating new connection: $CONN_DISPLAY_NAME"
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "https://api.fabric.microsoft.com/v1/connections" \
    -H "Authorization: Bearer $FABRIC_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" == "201" || "$HTTP_CODE" == "200" ]]; then
    log "SUCCESS: Connection Created. ID: $(echo "$BODY" | jq -r .id)"
else
    err "Failed to create. Code: $HTTP_CODE | Response: $BODY"
fi
