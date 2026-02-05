#!/bin/bash
# scripts/update_fabric_connection.sh
source ./db_env.sh
 
CONN_NAME="Conn_${TARGET_SPN_DISPLAY_NAME}"
SECRET_NAME="${TARGET_SPN_DISPLAY_NAME}-secret"
 
if [ -z "$FABRIC_TOKEN" ]; then echo "❌ FABRIC_TOKEN missing"; exit 1; fi
 
echo "--- Updating Existing Fabric Connection ---"
echo "  Target: $CONN_NAME"
 
# 1. Find Connection ID
echo "Searching for Connection ID..."
response=$(curl -s -X GET "${FABRIC_API_URL}/connections" -H "Authorization: Bearer ${FABRIC_TOKEN}")
 
CONN_ID=$(echo "$response" | jq -r --arg NAME "$CONN_NAME" '.value[] | select(.displayName == $NAME) | .id')
 
if [ -z "$CONN_ID" ] || [ "$CONN_ID" == "null" ]; then
    echo "❌ Error: Connection '$CONN_NAME' not found. Please create it manually once."
    exit 1
fi
 
echo "✅ Found ID: $CONN_ID"
 
# 2. Update Authentication (PATCH)
# We update the secret to ensure it points to the Key Vault
PAYLOAD=$(cat <<EOF
{
    "credentialDetails": {
        "useCallerCredentials": false,
        "authType": "DatabricksCredentials",
        "clientId": "${INTERNAL_SP_ID}", 
        "secret": {
            "type": "AzureKeyVault",
            "keyVaultUrl": "https://${KEYVAULT_NAME}.vault.azure.net/",
            "secretName": "${SECRET_NAME}" 
        }
    }
}
EOF
)
 
response=$(curl -s -w "%{http_code}" -X PATCH "${FABRIC_API_URL}/connections/${CONN_ID}" \
  -H "Authorization: Bearer ${FABRIC_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD")
 
http_code="${response: -3}"
 
if [ "$http_code" == "200" ]; then
    echo "✅ Success: Fabric Connection Updated."
else
    echo "❌ Error: Update failed (HTTP $http_code)."
    exit 1
fi
