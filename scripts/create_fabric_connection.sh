#!/bin/bash
set -euo pipefail

# === 1. Setup & Auth ===
log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }
err() { log "ERROR: $*" >&2; exit 1; }

source ./db_env.sh

log "Acquiring Fabric Token..."
# This is the reliable scope for Fabric/Power BI Admin APIs
FABRIC_TOKEN=$(az account get-access-token --resource "https://analysis.windows.net/powerbi/api" --query accessToken -o tsv)

# === 2. Get Credentials from KeyVault ===
# These are the *freshly rotated* secrets for the SPN we are creating the connection for
CLIENT_ID=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name "$ID_NAME" --query "value" -o tsv)
CLIENT_SECRET=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name "$SECRET_NAME" --query "value" -o tsv)

# === 3. Construct Payload (V1 Databricks Pattern) ===
# We use 'ShareableCloud'
# We use 'Databricks' as the type
# We map the hardcoded DB_HOST and DB_HTTP_PATH from Jenkins environment

INNER_CREDS=$(jq -n --arg user "$CLIENT_ID" --arg pass "$CLIENT_SECRET" \
  '{
    credentialType: "Basic",
    username: $user,
    password: $pass
  }')

PAYLOAD=$(jq -n \
  --arg name "$TARGET_SPN_DISPLAY_NAME" \
  --arg host "adb-7405609173671370.10.azuredatabricks.net" \
  --arg path "/sql/1.0/warehouses/559747c78f71249c" \
  --argjson creds "$INNER_CREDS" \
  '{
    connectivityType: "ShareableCloud",
    displayName: $name,
    privacyLevel: "Organizational",
    connectionDetails: {
      type: "AzureDatabricks", 
      creationMethod: "AzureDatabricks",
      parameters: [
        {
          name: "host",
          dataType: "Text",
          value: $host
        },
        {
          name: "httpPath",
          dataType: "Text",
          value: $path
        }
      ]
    },
    credentialDetails: {
      singleSignOnType: "None",
      connectionEncryption: "NotEncrypted",
      skipTestConnection: true,
      credentials: $creds
    }
  }' | jq -c)

# === 4. Execute Create (POST) ===
log "Creating Databricks Connection: $TARGET_SPN_DISPLAY_NAME"

RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "https://api.fabric.microsoft.com/v1/connections" \
    -H "Authorization: Bearer $FABRIC_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" == "201" || "$HTTP_CODE" == "200" ]]; then
    NEW_ID=$(echo "$BODY" | jq -r .id)
    log "SUCCESS: Connection Created. ID: $NEW_ID"
else
    err "Failed to create. Code: $HTTP_CODE | Response: $BODY"
fi
