#!/bin/bash
set -euo pipefail

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }
err() { log "ERROR: $*" >&2; exit 1; }

source ./db_env.sh

log "Acquiring Fabric Token..."
FABRIC_TOKEN=$(az account get-access-token --resource "https://api.fabric.microsoft.com/" --query accessToken -o tsv)

# === 1. Find Existing Connection ID ===
log "Searching for connection: $CONN_DISPLAY_NAME"
# Use URL Encoding %20 for spaces in the filter
SEARCH_URL="https://api.fabric.microsoft.com/v1/connections?\$filter=displayName%20eq%20'${TARGET_SPN_DISPLAY_NAME}'"
CONNECTION_ID=$(curl -s -H "Authorization: Bearer $FABRIC_TOKEN" "$SEARCH_URL" | jq -r '.value[0].id // empty')

if [ -z "$CONNECTION_ID" ]; then
    err "Connection not found. Run the creation script first."
fi

# === 2. Fetch New Secrets ===
CLIENT_ID=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name "$ID_NAME" --query "value" -o tsv)
CLIENT_SECRET=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name "$SECRET_NAME" --query "value" -o tsv)

# === 3. Construct Patch Payload ===
# For PATCH, we only send the credentialDetails to minimize errors
INNER_CREDS=$(jq -n --arg user "$CLIENT_ID" --arg pass "$CLIENT_SECRET" \
  '{"credentialData": [{"name": "username", "value": $user}, {"name": "password", "value": $pass}]}')

PAYLOAD=$(jq -n --argjson creds "$INNER_CREDS" \
  '{
    credentialDetails: {
      credentialType: "Basic",
      credentials: $creds,
      encryptedConnection: "Any",
      encryptionAlgorithm: "NONE",
      privacyLevel: "Organizational",
      useCallerCredentials: false
    }
  }' | jq -c)

# === 4. Execute Update (PATCH) ===
log "Rotating credentials for Connection ID: $CONNECTION_ID"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X PATCH \
    "https://api.fabric.microsoft.com/v1/connections/$CONNECTION_ID" \
    -H "Authorization: Bearer $FABRIC_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD")

if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "204" ]]; then
    log "SUCCESS: Credentials rotated."
else
    err "Rotation failed with HTTP Code: $HTTP_CODE"
fi
