#!/bin/bash
# Description: Rotate Microsoft Fabric connection credentials using Databricks Client Credentials
set -e
 
echo "-------------------------------------------------------"
echo " Microsoft Fabric Credential Rotation Started"
echo "-------------------------------------------------------"
 
# 1. Load environment variables
if [ -f db_env.sh ]; then
    . ./db_env.sh
else
    echo "ERROR: db_env.sh not found. Cannot proceed."
    exit 1
fi
 
# 2. Validate required variables
REQUIRED_VARS=(
  TARGET_SPN_DISPLAY_NAME
  AZURE_TENANT_ID
  KEYVAULT_NAME
  ID_NAME
  SECRET_NAME
)
 
for VAR in "${REQUIRED_VARS[@]}"; do
  if [ -z "${!VAR}" ]; then
    echo "ERROR: Missing variable $VAR in db_env.sh"
    exit 1
  fi
done
 
echo "Target SPN Display Name : $TARGET_SPN_DISPLAY_NAME"
echo "Key Vault Name         : $KEYVAULT_NAME"
echo "Client ID Secret Name  : $ID_NAME"
echo "Client Secret Name     : $SECRET_NAME"
 
# 3. Validate Azure Login Session
if ! az account show > /dev/null 2>&1; then
    echo "ERROR: Azure login required. Run az login first."
    exit 1
fi
 
# 4. Acquire Fabric API Token
echo "Acquiring Fabric API Token..."
 
FABRIC_TOKEN=$(az account get-access-token \
    --resource "https://api.fabric.microsoft.com/" \
    --query accessToken -o tsv)
 
if [ -z "$FABRIC_TOKEN" ]; then
    echo "ERROR: Failed to acquire Fabric access token"
    exit 1
fi
 
echo "Fabric token acquired successfully"
 
# 5. Build Fabric Connection Name
CLEAN_NAME=$(echo "$TARGET_SPN_DISPLAY_NAME" | tr ' ' '-')
FABRIC_CONN_NAME="db-$CLEAN_NAME"
 
echo "Looking for Fabric Connection: $FABRIC_CONN_NAME"
 
# 6. Fetch Fabric Connections
RESPONSE=$(curl -s \
  -H "Authorization: Bearer $FABRIC_TOKEN" \
  "https://api.fabric.microsoft.com/v1/connections")
 
if [ -z "$RESPONSE" ]; then
    echo "ERROR: Unable to fetch Fabric connections"
    exit 1
fi
 
# 7. Extract Connection ID
CONNECTION_ID=$(echo "$RESPONSE" | jq -r ".value[] | select(.displayName==\"$FABRIC_CONN_NAME\") | .id")
 
if [ -z "$CONNECTION_ID" ] || [ "$CONNECTION_ID" = "null" ]; then
    echo "ERROR: Fabric Connection '$FABRIC_CONN_NAME' not found"
    exit 1
fi
 
echo "Fabric Connection ID: $CONNECTION_ID"
 
# 8. Fetch Client ID from Key Vault
echo "Fetching Client ID from Key Vault..."
 
CLIENT_ID=$(az keyvault secret show \
  --vault-name "$KEYVAULT_NAME" \
  --name "$ID_NAME" \
  --query "value" -o tsv)
 
if [ -z "$CLIENT_ID" ]; then
    echo "ERROR: Client ID secret not found in Key Vault"
    exit 1
fi
 
echo "Client ID retrieved successfully"
 
# 9. Fetch Client Secret from Key Vault
echo "Fetching Client Secret from Key Vault..."
 
CLIENT_SECRET=$(az keyvault secret show \
  --vault-name "$KEYVAULT_NAME" \
  --name "$SECRET_NAME" \
  --query "value" -o tsv)
 
if [ -z "$CLIENT_SECRET" ]; then
    echo "ERROR: Client Secret not found in Key Vault"
    exit 1
fi
 
echo "Client Secret retrieved successfully"
 
# 10. Build Correct Fabric Payload — Databricks Client Credentials
echo "Building Fabric credential payload..."
 
PAYLOAD=$(jq -n \
  --arg tenant "$AZURE_TENANT_ID" \
  --arg clientId "$CLIENT_ID" \
  --arg secret "$CLIENT_SECRET" \
'{
  "credentialDetails": {
    "useCallerCredentials": false,
    "credentials": {
      "credentialType": "DatabricksClientCredentials",
      "tenantId": $tenant,
      "clientId": $clientId,
      "clientSecret": $secret
    }
  }
}')
 
# Debug payload (hide secret)
echo "---------------- PAYLOAD DEBUG ----------------"
echo "$PAYLOAD" | jq .
echo "------------------------------------------------"
 
# 11. PATCH Fabric Credentials
echo "Updating Fabric connection credentials..."
 
PATCH_RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X PATCH \
  -H "Authorization: Bearer $FABRIC_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \
  "https://api.fabric.microsoft.com/v1/connections/$CONNECTION_ID")
 
HTTP_STATUS=$(echo "$PATCH_RESPONSE" | tail -n1 | cut -d':' -f2)
BODY=$(echo "$PATCH_RESPONSE" | sed '$d')
 
# 12. Validate Response
if [ "$HTTP_STATUS" -eq 200 ]; then
    echo "SUCCESS: Fabric connection credentials updated"
else
    echo "FAILURE: Fabric API returned HTTP $HTTP_STATUS"
    echo "Response Body:"
    echo "$BODY"
    exit 1
fi
 
echo "-------------------------------------------------------"
echo " Rotation Completed Successfully"
echo "-------------------------------------------------------"
