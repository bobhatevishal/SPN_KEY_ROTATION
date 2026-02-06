#!/bin/bash
# Description: Safely updates Microsoft Fabric Databricks OAuth credentials
# Behavior: Patch only if supported, otherwise skip
# Requirement: jq, az, curl
set -e
 
# Load environment state
if [ -f db_env.sh ]; then
    . ./db_env.sh
else
    echo "ERROR: db_env.sh not found. Ensure previous stages exported credentials."
    exit 1
fi
 
echo "-------------------------------------------------------"
echo "Fabric Integration: Scanning & Syncing Databricks Credentials"
echo "-------------------------------------------------------"
 
# Authenticate Fabric API
FABRIC_TOKEN=$(az account get-access-token \
    --resource https://api.fabric.microsoft.com \
    --query accessToken -o tsv)
 
# Build connection name
CLEAN_NAME=$(echo "$TARGET_SPN_DISPLAY_NAME" | tr ' ' '-')
FABRIC_CONN_NAME="db-$CLEAN_NAME"
 
echo "Searching for Connection Name: $FABRIC_CONN_NAME"
 
# Fetch Fabric connections
RESPONSE=$(curl -s -X GET \
  -H "Authorization: Bearer $FABRIC_TOKEN" \
  "https://api.fabric.microsoft.com/v1/connections")
 
# Extract connection ID
CONNECTION_ID=$(echo "$RESPONSE" | jq -r ".value[] | select(.displayName==\"$FABRIC_CONN_NAME\") | .id // empty")
 
# If connection does not exist — skip safely
if [ -z "$CONNECTION_ID" ]; then
    echo "INFO: Fabric connection '$FABRIC_CONN_NAME' not found. Skipping."
    exit 0
fi
 
# Extract existing credential type
EXISTING_CRED_TYPE=$(echo "$RESPONSE" | jq -r ".value[] | select(.displayName==\"$FABRIC_CONN_NAME\") | .credentialDetails.credentialType // empty")
 
echo "Connection Found. ID: $CONNECTION_ID"
echo "Existing Credential Type: $EXISTING_CRED_TYPE"
 
# If not OAuth SPN — skip (do NOT delete)
if [ "$EXISTING_CRED_TYPE" != "DatabricksClientCredentials" ]; then
    echo "WARNING: Connection is not OAuth SPN type."
    echo "Skipping update to avoid breaking existing auth."
    echo "No action taken."
    exit 0
fi
 
# Build PATCH payload
PAYLOAD=$(cat <<EOF
{
  "credentialDetails": {
    "credentialType": \"OAuth2\",
    "credentials": {
      "servicePrincipalId": "$TARGET_APPLICATION_ID",
      "servicePrincipalKey": "$FINAL_OAUTH_SECRET"
    },
    "privacyLevel": "Private"
  }
}
EOF
)
 
DEBUG_FILE="fabric_patch_error.json"
 
echo "Patching Fabric Connection ID: $CONNECTION_ID"
 
PATCH_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X PATCH \
  -H "Authorization: Bearer $FABRIC_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"credentialDetails\": {
      \"credentialType\": \"OAuth2\",
      \"credentials\": {
        \"clientSecret\": \"$FINAL_OAUTH_SECRET\",
        \"clientId\": \"$TARGET_APPLICATION_ID\"
      },
      \"encryptedConnection\": \"Encrypted\",
      \"encryptionAlgorithm\": \"None\",
      \"privacyLevel\": \"Private\",
      \"skipTestConnection\": true
    }
  }" \
  "https://api.fabric.microsoft.com/v1/connections/$CONNECTION_ID")
 
if [[ "$PATCH_CODE" =~ ^20 ]]; then
    echo "SUCCESS: Fabric credentials updated safely."
    rm -f "$DEBUG_FILE"
    exit 0
else
    echo "ERROR: PATCH failed (HTTP $PATCH_CODE)"
    echo "--- Fabric Error Response ---"
    cat "$DEBUG_FILE"
    echo "--------------------------------"
    echo "Skipping failure to avoid pipeline break."
    exit 0
fi
