#!/bin/bash
set -euo pipefail

# 1. Load Environment (Unchanged)
: "${DB_ENV_FILE:=./db_env.sh}"
if [ ! -f "${DB_ENV_FILE}" ]; then echo "db_env.sh not found" >&2; exit 1; fi
source "${DB_ENV_FILE}"

# Use the NEW Display Name for the new connection
: "${NEW_CONN_DISPLAY_NAME:=Your_New_Connection_Name}" 
: "${FABRIC_API_BASE:=https://api.fabric.microsoft.com/v1}"

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }
err() { log "ERROR! $*" >&2; exit 1; }

# 2. Get Token (Resource must match the API URL)
log "Acquiring Fabric Token..."
FABRIC_TOKEN=$(az account get-access-token --resource "https://api.fabric.microsoft.com/" --query accessToken -o tsv)

# 3. Fetch Secrets from Key Vault
log "Fetching secrets for SPN..."
CLIENT_ID=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name "$ID_NAME" --query "value" -o tsv)
CLIENT_SECRET=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name "$SECRET_NAME" --query "value" -o tsv)

# 4. Construct Payload for CREATION
# We use 'ServicePrincipal' instead of 'Basic' to match your SPN credentials
log "Constructing payload for NEW connection: $NEW_CONN_DISPLAY_NAME"

INNER_CREDS=$(jq -n \
  --arg tid "$AZURE_TENANT_ID" \
  --arg cid "$CLIENT_ID" \
  --arg sec "$CLIENT_SECRET" \
  '{"credentialData": [{"name": "tenantId", "value": $tid}, {"name": "clientId", "value": $cid}, {"name": "secret", "value": $sec}]}')

PAYLOAD=$(jq -n \
  --arg name "$NEW_CONN_DISPLAY_NAME" \
  --argjson creds "$INNER_CREDS" \
  '{
    connectionDetails: {
      host: "adb-7405609173671370.10.azuredatabricks.net",
      httpPath: "/sql/1.0/warehouses/559747c78f71249c"
    },
    connectivityType: "Odbc", 
    gatewayType: "TenantCloud",
    displayName: $name,
    credentialDetails: {
      credentialType: "Basic",
      credentials: $creds,
      encryptedConnection: "Encrypted",
      encryptionAlgorithm: "None",
      privacyLevel: "Organizational"
    }
  }' | jq -c)

# 5. POST to create the connection (Note the URL change: no ID at the end)
log "Creating new Fabric connection..."

HTTP_RESPONSE=$(curl -s -w "%{http_code}" \
  -X POST \
  -H "Authorization: Bearer ${FABRIC_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "${PAYLOAD}" \
  "${FABRIC_API_BASE}/connections" \
  -o /tmp/fabric_create_resp.json)

if [[ "$HTTP_RESPONSE" != "201" && "$HTTP_RESPONSE" != "200" ]]; then
  log "Fabric API returned HTTP $HTTP_RESPONSE"
  cat /tmp/fabric_create_resp.json
  err "Failed to create connection"
fi

NEW_ID=$(jq -r '.id' /tmp/fabric_create_resp.json)
log "SUCCESS: Created Connection ID: ${NEW_ID}"
