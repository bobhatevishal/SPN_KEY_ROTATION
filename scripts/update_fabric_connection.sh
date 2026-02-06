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
echo "Force-updating credential to OAuth2 (Databricks Client Credentials)..."
 
# 5. Push the new secret to Fabric
# We EXPLICITLY set credentialType to "OAuth2" to overwrite the existing "Basic" type.
PATCH_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X PATCH \
  -H "Authorization: Bearer $FABRIC_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"credentialDetails\": {
      \"credentialType\": \"OAuth2\",
      \"credentials\": {
        \"clientSecret\": \"$FINAL_OAUTH_SECRET\",
        \"clientId\": \"842439d6-518c-42a5-af01-c492d638c6c9\"
      },
      \"encryptedConnection\": \"Encrypted\",
      \"encryptionAlgorithm\": \"None\",
      \"privacyLevel\": \"Private\",
      \"skipTestConnection\": true
    }
  }" \
  "https://api.fabric.microsoft.com/v1/connections/$CONNECTION_ID")
 
if [ "$PATCH_CODE" -eq 200 ] || [ "$PATCH_CODE" -eq 204 ]; then
    echo "SUCCESS: Connection converted to OAuth2 and updated successfully."
else
    echo "FAILURE: Fabric API returned HTTP status $PATCH_CODE"
    # Optional: Print response for debugging if it fails
    # curl ... (same command without -o /dev/null)
    exit 1
fi
