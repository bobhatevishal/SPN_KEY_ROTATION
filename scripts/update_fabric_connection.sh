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
 
# If not already a Databricks type — skip to avoid breaking existing manual setups
if [ "$EXISTING_CRED_TYPE" != "DatabricksClientCredentials" ]; then
    echo "WARNING: Connection is not DatabricksClientCredentials type (Found: $EXISTING_CRED_TYPE)."
    echo "Skipping update to avoid breaking existing auth."
    exit 0
fi
 
echo "Patching Fabric Connection ID: $CONNECTION_ID"
 
# Integrated PATCH using DatabricksClientCredentials schema
# We capture the response body and the HTTP status code separately
RAW_RESPONSE=$(curl -s -X PATCH \
  -H "Authorization: Bearer $FABRIC_TOKEN" \
  -H "Content-Type: application/json" \
  -w "\n%{http_code}" \
  -d "{
    \"credentialDetails\": {
      \"credentialType\": \"DatabricksClientCredentials\",
      \"databricksClientCredentials\": {
        \"clientId\": \"$TARGET_APPLICATION_ID\",
        \"clientSecret\": \"$FINAL_OAUTH_SECRET\"
      },
      \"privacyLevel\": \"Private\",
      \"skipTestConnection\": true
    }
  }" \
  "https://api.fabric.microsoft.com/v1/connections/$CONNECTION_ID")
 
# Split status code from body
PATCH_CODE=$(echo "$RAW_RESPONSE" | tail -n1)
PATCH_BODY=$(echo "$RAW_RESPONSE" | sed '$d')
 
if [[ "$PATCH_CODE" =~ ^20 ]]; then
    echo "SUCCESS: Fabric credentials updated safely."
    exit 0
else
    echo "ERROR: PATCH failed (HTTP $PATCH_CODE)"
    echo "--- Fabric Error Response ---"
    echo "$PATCH_BODY" | jq . 2>/dev/null || echo "$PATCH_BODY"
    echo "--------------------------------"
    # Exit 0 to prevent Jenkins pipeline break as per your requirement
    exit 0
fi
