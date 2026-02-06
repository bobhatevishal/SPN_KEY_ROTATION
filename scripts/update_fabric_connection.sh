#!/bin/bash
set -e

# 1. Load environment (contains FINAL_OAUTH_SECRET and TARGET_APPLICATION_ID)
[ -f db_env.sh ] && . ./db_env.sh

# 2. Force-clean variables (Removes hidden spaces/newlines that cause 400 errors)
FINAL_OAUTH_SECRET=$(echo "$FINAL_OAUTH_SECRET" | tr -d '\r\n ')
TARGET_APPLICATION_ID=$(echo "$TARGET_APPLICATION_ID" | tr -d '\r\n ')

echo "-------------------------------------------------------"
echo "Fabric Integration: Syncing Credentials for ID 1c2e7a3a"
echo "-------------------------------------------------------"

# 3. Get Fabric Token
FABRIC_TOKEN=$(az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv)

# 4. Fetch the existing connection metadata
# We MUST send the existing 'connectionDetails' back to the API during the PATCH
CONN_PATH="https://api.fabric.microsoft.com/v1/connections/1c2e7a3a-1434-4311-b39a-a392fc192be5"
ALL_METADATA=$(curl -s -X GET -H "Authorization: Bearer $FABRIC_TOKEN" "$CONN_PATH")

# Extract the connectionDetails block (Host/Path)
CONNECTION_DETAILS=$(echo "$ALL_METADATA" | jq -c '.connectionDetails')

echo "Updating Connection with Data Source Path: $CONNECTION_DETAILS"

# 5. Execute the PATCH with the COMPLETE valid input structure
PATCH_RESPONSE=$(curl -s -w "\n%{http_code}" -X PATCH \
  -H "Authorization: Bearer $FABRIC_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"connectionDetails\": $CONNECTION_DETAILS,
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
  "$CONN_PATH")

# 6. Parse Results
PATCH_CODE=$(echo "$PATCH_RESPONSE" | tail -n1)
PATCH_BODY=$(echo "$PATCH_RESPONSE" | sed '$d')

if [ "$PATCH_CODE" -eq 200 ] || [ "$PATCH_CODE" -eq 204 ]; then
    echo "SUCCESS: Fabric Connection 1c2e7a3a updated."
else
    echo "FAILURE: Status $PATCH_CODE"
    echo "API Response: $PATCH_BODY"
    exit 1
fi
