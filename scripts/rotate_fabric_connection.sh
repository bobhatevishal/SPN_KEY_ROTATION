#!/bin/bash
set -euo pipefail

# === 1. Setup & Auth ===
log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }
err() { log "ERROR: $*" >&2; exit 1; }

source ./db_env.sh

log "Acquiring Fabric Token..."
# This is the reliable scope for Fabric/Power BI Admin APIs
FABRIC_TOKEN=$(az account get-access-token --resource "https://analysis.windows.net/powerbi/api" --query accessToken -o tsv)

# === 2. Verify Connection ID ===
if [ -z "${EXISTING_CONNECTION_ID:-}" ]; then
    err "EXISTING_CONNECTION_ID is not set. Cannot patch."
fi

# === 3. Get Credentials from KeyVault ===
CLIENT_ID=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name "$ID_NAME" --query "value" -o tsv)
CLIENT_SECRET=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name "$SECRET_NAME" --query "value" -o tsv)

# === 4. Construct Payload (PATCH) ===
# Only credentialDetails are needed for rotation
INNER_CREDS=$(jq -n --arg user "$CLIENT_ID" --arg pass "$CLIENT_SECRET" \
  '{
    credentialType: "Basic",
    username: $user,
    password: $pass
  }')

PAYLOAD=$(jq -n --argjson creds "$INNER_CREDS" \
  '{
    credentialDetails: {
      singleSignOnType: "None",
      connectionEncryption: "NotEncrypted",
      skipTestConnection: true,
      credentials: $creds
    }
  }' | jq -c)

# === 5. Execute Update (PATCH) ===
log "Rotating credentials for Connection ID: $EXISTING_CONNECTION_ID"

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X PATCH \
    "https://api.fabric.microsoft.com/v1/connections/$EXISTING_CONNECTION_ID" \
    -H "Authorization: Bearer $FABRIC_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD")

if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "204" ]]; then
    log "SUCCESS: Credentials rotated successfully."
else
    err "Rotation failed with HTTP Code: $HTTP_CODE"
fi
