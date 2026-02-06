#!/bin/bash
# scripts/update_fabric_connection.sh
 
# Description: Safely updates Fabric Connection using Key Vault reference
# Requirement: jq, curl
 
set -e
 
# 1. Load Environment & Token
if [ -f db_env.sh ]; then
    . ./db_env.sh
else
    echo "❌ ERROR: db_env.sh not found."
    exit 1
fi
 
# Ensure we have the token from the previous pipeline stage
if [ -z "$FABRIC_TOKEN" ]; then
    echo "❌ ERROR: FABRIC_TOKEN is missing. Run get_fabric_token.sh first."
    exit 1
fi
 
echo "-------------------------------------------------------"
echo "Fabric Integration: Syncing Databricks Credentials"
echo "-------------------------------------------------------"
 
# 2. Define Naming Convention
# Must match the name used in creation (e.g., "Conn_automation-spn")
FABRIC_CONN_NAME="Conn_${TARGET_SPN_DISPLAY_NAME}"
echo "Searching for Connection Name: $FABRIC_CONN_NAME"
 
# 3. Find Connection ID
RESPONSE=$(curl -s -X GET \
  -H "Authorization: Bearer $FABRIC_TOKEN" \
  "https://api.fabric.microsoft.com/v1/connections")
 
# Extract ID safely
CONNECTION_ID=$(echo "$RESPONSE" | jq -r --arg NAME "$FABRIC_CONN_NAME" '.value[] | select(.displayName==$NAME) | .id')
 
# If connection does not exist — skip safely
if [ -z "$CONNECTION_ID" ] || [ "$CONNECTION_ID" == "null" ]; then
    echo "⚠️ INFO: Fabric connection '$FABRIC_CONN_NAME' not found."
    echo "      Skipping update (It might need to be created first)."
    exit 0
fi
 
echo "✅ Connection Found. ID: $CONNECTION_ID"
 
# 4. Construct Payload (The Fix)
# We use the variable directly here. We point to Key Vault for security.
PAYLOAD=$(cat <<EOF
{
  "credentialDetails": {
    "useCallerCredentials": false,
    "authType": "DatabricksCredentials",
    "clientId": "${INTERNAL_SP_ID}",
    "secret": {
        "type": "AzureKeyVault",
        "keyVaultUrl": "https://${KEYVAULT_NAME}.vault.azure.net/",
        "secretName": "${TARGET_SPN_DISPLAY_NAME}-secret"
    }
  }
}
EOF
)
 
# 5. Execute PATCH (The Fix)
DEBUG_FILE="fabric_patch_response.txt"
 
echo "Patching Connection..."
 
# -w %{http_code} captures the status code
# -o "$DEBUG_FILE" captures the response body (so we can read it on error)
HTTP_CODE=$(curl -s -o "$DEBUG_FILE" -w "%{http_code}" -X PATCH \
  -H "Authorization: Bearer $FABRIC_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \
  "https://api.fabric.microsoft.com/v1/connections/$CONNECTION_ID")
 
# 6. Handle Result
if [[ "$HTTP_CODE" =~ ^20 ]]; then
    echo "✅ SUCCESS: Fabric credentials updated."
    rm -f "$DEBUG_FILE"
    exit 0
else
    echo "❌ ERROR: PATCH failed (HTTP $HTTP_CODE)"
    echo "--- Fabric Error Response ---"
    cat "$DEBUG_FILE"
    echo -e "\n--------------------------------"
    # Fail the pipeline so we know credentials are out of sync
    exit 1
fi
