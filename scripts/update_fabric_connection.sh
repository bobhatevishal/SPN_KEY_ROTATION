#!/bin/bash
# Description: Safely updates Microsoft Fabric Databricks OAuth credentials
# Behavior: Patch only if supported, otherwise skip
# Requirement: jq, az, curl
set -e

# 1. Load environment state
if [ -f db_env.sh ]; then
    . ./db_env.sh
else
    echo "ERROR: db_env.sh not found. Ensure previous stages exported credentials."
    exit 1
fi

# 2. CLEAN VARIABLES (Crucial to prevent HTTP 400)
# This removes any hidden newlines, carriage returns, or spaces
FINAL_OAUTH_SECRET=$(echo "$FINAL_OAUTH_SECRET" | tr -d '\r\n ')
TARGET_APPLICATION_ID=$(echo "$TARGET_APPLICATION_ID" | tr -d '\r\n ')

echo "-------------------------------------------------------"
echo "Fabric Integration: Scanning & Syncing Databricks Credentials"
echo "-------------------------------------------------------"

# 3. Authenticate Fabric API
FABRIC_TOKEN=$(az account get-access-token \
    --resource https://api.fabric.microsoft.com \
    --query accessToken -o tsv)

# 4. Build connection name
CLEAN_NAME=$(echo "$TARGET_SPN_DISPLAY_NAME" | tr ' ' '-')
FABRIC_CONN_NAME="db-$CLEAN_NAME"

echo "Searching for Connection Name: $FABRIC_CONN_NAME"

# 5. Fetch Fabric connections
RESPONSE=$(curl -s -X GET \
  -H "Authorization: Bearer $FABRIC_TOKEN" \
  "https://api.fabric.microsoft.com/v1/connections")

# 6. Extract connection ID
CONNECTION_ID=$(echo "$RESPONSE" | jq -r ".value[] | select(.displayName==\"$FABRIC_CONN_NAME\") | .id // empty")

if [ -z "$CONNECTION_ID" ]; then
    echo "INFO: Fabric connection '$FABRIC_CONN_NAME' not found. Skipping."
    exit 0
fi

echo "Connection Found. ID: $CONNECTION_ID"
echo "Force-updating to Databricks Client Credentials (OAuth2)..."

# 7. Push the new secret to Fabric
# We use 'format: DatabricksClientCredentials' to tell Fabric this is an SPN flow.
# We also omit privacyLevel/encryption to avoid validation conflicts.
PATCH_RESPONSE=$(curl -s -w "\n%{http_code}" -X PATCH \
  -H "Authorization: Bearer $FABRIC_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"credentialDetails\": {
      \"credentialType\": \"OAuth2\",
      \"format\": \"DatabricksClientCredentials\",
      \"credentials\": {
        \"clientSecret\": \"$FINAL_OAUTH_SECRET\",
        \"clientId\": \"$TARGET_APPLICATION_ID\"
      },
      \"skipTestConnection\": true
    }
  }" \
  "https://api.fabric.microsoft.com/v1/connections/$CONNECTION_ID")

# 8. Parse Response
PATCH_CODE=$(echo "$PATCH_RESPONSE" | tail -n1)
PATCH_BODY=$(echo "$PATCH_RESPONSE" | sed '$d')

if [ "$PATCH_CODE" -eq 200 ] || [ "$PATCH_CODE" -eq 204 ]; then
    echo "SUCCESS: Connection updated to Databricks Client Credentials."
else
    echo "-------------------------------------------------------"
    echo "FAILURE: Fabric API returned HTTP status $PATCH_CODE"
    echo "Detailed Error Message: $PATCH_BODY"
    echo "-------------------------------------------------------"
    echo "TROUBLESHOOTING TIPS:"
    echo "1. Verify the Jenkins SPN is an 'Owner' of connection $CONNECTION_ID."
    echo "2. Check if 'Service principals can use Fabric APIs' is enabled in Fabric Admin Tenant settings."
    exit 1
fi
