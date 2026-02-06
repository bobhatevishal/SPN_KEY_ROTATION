#!/bin/bash
set -e

# 1. Load environment state
if [ -f db_env.sh ]; then
    . ./db_env.sh
else
    echo "ERROR: db_env.sh not found."
    exit 1
fi

# 2. Clean variables (Critical)
FINAL_OAUTH_SECRET=$(echo "$FINAL_OAUTH_SECRET" | tr -d '\r\n ')
TARGET_APPLICATION_ID=$(echo "$TARGET_APPLICATION_ID" | tr -d '\r\n ')

echo "-------------------------------------------------------"
echo "Fabric Integration: Syncing Databricks Credentials"
echo "-------------------------------------------------------"

# 3. Authenticate Fabric API
FABRIC_TOKEN=$(az account get-access-token \
    --resource https://api.fabric.microsoft.com \
    --query accessToken -o tsv)

# 4. Identify Connection
CLEAN_NAME=$(echo "$TARGET_SPN_DISPLAY_NAME" | tr ' ' '-')
FABRIC_CONN_NAME="db-$CLEAN_NAME"

# 5. Fetch current connection metadata to get the 'connectionDetails'
# This is required because Fabric often rejects patches that lack the original host path.
ALL_CONNS=$(curl -s -X GET \
  -H "Authorization: Bearer $FABRIC_TOKEN" \
  "https://api.fabric.microsoft.com/v1/connections")

# Extract Connection ID and current Connection Details (the host/path info)
CONNECTION_ID=$(echo "$ALL_CONNS" | jq -r ".value[] | select(.displayName==\"$FABRIC_CONN_NAME\") | .id // empty")
CONN_METADATA=$(echo "$ALL_CONNS" | jq -c ".value[] | select(.displayName==\"$FABRIC_CONN_NAME\") | .connectionDetails")

if [ -z "$CONNECTION_ID" ]; then
    echo "INFO: Fabric connection '$FABRIC_CONN_NAME' not found. Skipping."
    exit 0
fi

echo "Connection Found. ID: $CONNECTION_ID"

# 6. Push the update
# We include 'connectionDetails' and 'format' to satisfy the 'InvalidInput' error.
PATCH_RESPONSE=$(curl -s -w "\n%{http_code}" -X PATCH \
  -H "Authorization: Bearer $FABRIC_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"connectionDetails\": $CONN_METADATA,
    \"credentialDetails\": {
      \"credentialType\": \"OAuth2\",
      \"format\": \"DatabricksClientCredentials\",
      \"credentials\": {
        \"clientSecret\": \"$FINAL_OAUTH_SECRET\",
        \"clientId\": \"$TARGET_APPLICATION_ID\"
      },
      \"encryptionAlgorithm\": \"None\",
      \"privacyLevel\": \"Private\",
      \"skipTestConnection\": true
    }
  }" \
  "https://api.fabric.microsoft.com/v1/connections/$CONNECTION_ID")

PATCH_CODE=$(echo "$PATCH_RESPONSE" | tail -n1)
PATCH_BODY=$(echo "$PATCH_RESPONSE" | sed '$d')

if [ "$PATCH_CODE" -eq 200 ] || [ "$PATCH_CODE" -eq 204 ]; then
    echo "SUCCESS: Connection updated with new Key Vault secret."
else
    echo "FAILURE: Fabric API returned $PATCH_CODE"
    echo "Error Detail: $PATCH_BODY"
    exit 1
fi
