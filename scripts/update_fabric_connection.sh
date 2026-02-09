#!/bin/bash
# Description: Rotate Microsoft Fabric connection credentials using Basic/Extension Schema
set -e

echo "-------------------------------------------------------"
echo " Microsoft Fabric Credential Rotation Started"
echo "-------------------------------------------------------"

# 1. Load environment variables
if [ -f db_env.sh ]; then
    . ./db_env.sh
else
    echo "ERROR: db_env.sh not found."
    exit 1
fi

# 2. Validate required variables
REQUIRED_VARS=(TARGET_SPN_DISPLAY_NAME KEYVAULT_NAME ID_NAME SECRET_NAME)
for VAR in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!VAR}" ]; then echo "ERROR: Missing $VAR"; exit 1; fi
done

# 3. Acquire Fabric API Token
echo "Acquiring Fabric API Token..."
FABRIC_TOKEN=$(az account get-access-token --resource "https://api.fabric.microsoft.com/" --query accessToken -o tsv)

# 4. Fetch Connection ID
CLEAN_NAME=$(echo "$TARGET_SPN_DISPLAY_NAME" | tr ' ' '-')
FABRIC_CONN_NAME="db-$CLEAN_NAME"
RESPONSE=$(curl -s -H "Authorization: Bearer $FABRIC_TOKEN" "https://api.fabric.microsoft.com/v1/connections")
CONNECTION_ID=$(echo "$RESPONSE" | jq -r ".value[] | select(.displayName==\"$FABRIC_CONN_NAME\") | .id")

if [ -z "$CONNECTION_ID" ] || [ "$CONNECTION_ID" = "null" ]; then
    echo "ERROR: Connection $FABRIC_CONN_NAME not found"; exit 1
fi

# 5. Fetch Secrets from Key Vault
CLIENT_ID=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name "$ID_NAME" --query "value" -o tsv)
CLIENT_SECRET=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name "$SECRET_NAME" --query "value" -o tsv)

# 6. Build the NEW Approach Payload (Basic Extension)
# This mimics the "username/password" structure your dump revealed
echo "Building Fabric credential payload (Extension/Basic Type)..."

INNER_CREDENTIALS=$(jq -nc \
  --arg user "$CLIENT_ID" \
  --arg pass "$CLIENT_SECRET" \
  '{"credentialData": [{"name": "username", "value": $user}, {"name": "password", "value": $pass}]}')

PAYLOAD=$(jq -n \
  --arg creds "$INNER_CREDENTIALS" \
  '{
    "credentialDetails": {
      "credentialType": "Basic",
      "credentials": $creds,
      "encryptedConnection": "Any",
      "encryptionAlgorithm": "NONE",
      "privacyLevel": "Organizational",
      "useCallerCredentials": false
    }
  }')

echo "---------------- PAYLOAD DEBUG ----------------"
echo "$PAYLOAD" | jq '.credentialDetails.credentials="***STRICT_STRING_HIDDEN***"'
echo "------------------------------------------------"

# 7. Update via PATCH
# NOTE: We use the base connection URL, not the /credentials sub-path for this type
echo "Updating Fabric connection..."
PATCH_RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X PATCH \
  -H "Authorization: Bearer $FABRIC_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \
  "https://api.fabric.microsoft.com/v1/connections/$CONNECTION_ID")

HTTP_STATUS=$(echo "$PATCH_RESPONSE" | tail -n1 | cut -d':' -f2)
BODY=$(echo "$PATCH_RESPONSE" | sed '$d')

if [ "$HTTP_STATUS" -eq 200 ] || [ "$HTTP_STATUS" -eq 204 ]; then
    echo "SUCCESS: Fabric credentials updated."
else
    echo "FAILURE: HTTP $HTTP_STATUS"
    echo "Response: $BODY"
    exit 1
fi
