#!/bin/bash
set -e

# 1. Load environment (contains FINAL_OAUTH_SECRET, TARGET_APPLICATION_ID, and optionally FABRIC_CONN_ID)
[ -f db_env.sh ] && . ./db_env.sh

# 2. CONFIGURATION: Define the Connection ID here or in db_env.sh
# Replace this ID with the one you verified from the Fabric Portal
FABRIC_CONN_ID="10ba9ab7-2832-4023-af43-2d38a6adda69"

# 3. Force-clean variables
FINAL_OAUTH_SECRET=$(echo "$FINAL_OAUTH_SECRET" | tr -d '\r\n ')
TARGET_APPLICATION_ID=$(echo "$TARGET_APPLICATION_ID" | tr -d '\r\n ')
FABRIC_CONN_ID=$(echo "$FABRIC_CONN_ID" | tr -d '\r\n ')

echo "-------------------------------------------------------"
echo "Fabric Integration: Syncing Credentials"
echo "Target Connection ID: $FABRIC_CONN_ID"
echo "-------------------------------------------------------"

# Check if Connection ID is empty
if [ -z "$FABRIC_CONN_ID" ]; then
    echo "ERROR: FABRIC_CONN_ID is not set. Please update the script or db_env.sh."
    exit 1
fi

# 4. Get Fabric Token
FABRIC_TOKEN=$(az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv)

# 5. Fetch the existing connection metadata
CONN_PATH="https://api.fabric.microsoft.com/v1/connections/$FABRIC_CONN_ID"
ALL_METADATA=$(curl -s -X GET -H "Authorization: Bearer $FABRIC_TOKEN" "$CONN_PATH")

# DEBUG: See what the API actually returns
echo "DEBUG: API Response for GET: $ALL_METADATA"

CONNECTION_DETAILS=$(echo "$ALL_METADATA" | jq -c '.connectionDetails')

# SAFETY CHECK: Stop if connection details are missing
if [ "$CONNECTION_DETAILS" == "null" ] || [ -z "$CONNECTION_DETAILS" ]; then
    echo "ERROR: Could not retrieve connectionDetails for ID: $FABRIC_CONN_ID"
    echo "Reason: The API returned null. This usually means the ID is wrong or the Jenkins SPN lacks permissions."
    exit 1
fi

echo "Updating Connection with Data Source Path: $CONNECTION_DETAILS"

# 6. Execute the PATCH
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

# 7. Parse Results
PATCH_CODE=$(echo "$PATCH_RESPONSE" | tail -n1)
PATCH_BODY=$(echo "$PATCH_RESPONSE" | sed '$d')

if [ "$PATCH_CODE" -eq 200 ] || [ "$PATCH_CODE" -eq 204 ]; then
    echo "SUCCESS: Fabric Connection $FABRIC_CONN_ID updated."
else
    echo "FAILURE: Status $PATCH_CODE"
    echo "API Response: $PATCH_BODY"
    exit 1
fi
