#!/bin/bash
# Description: Updates Microsoft Fabric Cloud Connections with new OAuth secrets
set -e

# 1. Load the state from the previous Databricks/KeyVault stages
[ -f db_env.sh ] && . ./db_env.sh

echo "-------------------------------------------------------"
echo "Fabric Integration: Updating Connection for $TARGET_SPN_DISPLAY_NAME"
echo "-------------------------------------------------------"

# 2. Authenticate for Microsoft Fabric (Power BI API)
# We use the service principal login established in the get_token.sh stage
FABRIC_TOKEN=$(az account get-access-token \
    --resource https://analysis.windows.net/powerbi/api \
    --query accessToken -o tsv)

# 3. Match the Fabric Connection Name
# As per your screenshot: 'db-automation-spn'
# Logic: Use the 'db-' prefix + the sanitized SPN name (spaces to dashes)
CLEAN_NAME=$(echo "$TARGET_SPN_DISPLAY_NAME" | tr ' ' '-')
FABRIC_CONN_NAME="db-$CLEAN_NAME"

echo "Searching for Connection Name: $FABRIC_CONN_NAME"

# 4. Locate the Connection ID via Fabric API
# We filter the tenant's connections to find the one matching your naming convention
RESPONSE=$(curl -s -X GET \
  -H "Authorization: Bearer $FABRIC_TOKEN" \
  "https://api.fabric.microsoft.com/v1/connections")

CONNECTION_ID=$(echo "$RESPONSE" | jq -r ".value[] | select(.displayName==\"$FABRIC_CONN_NAME\") | .id // empty")

if [ -z "$CONNECTION_ID" ]; then
    echo "ERROR: Fabric Connection '$FABRIC_CONN_NAME' not found."
    echo "Verify the connection exists in the 'Manage Connections and Gateways' portal."
    exit 1
fi

# 5. Push the new secret to Fabric
# This patches the ServicePrincipal credentials with the new $FINAL_OAUTH_SECRET
echo "Patching Fabric Connection ID: $CONNECTION_ID"

PATCH_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X PATCH \
  -H "Authorization: Bearer $FABRIC_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"credentialDetails\": {
      \"credentialType\": \"ServicePrincipal\",
      \"credentials\": {
        \"servicePrincipalKey\": \"$FINAL_OAUTH_SECRET\"
      },
      \"encryptedConnection\": \"Encrypted\",
      \"encryptionAlgorithm\": \"None\",
      \"privacyLevel\": \"Organizational\"
    }
  }" \
  "https://api.fabric.microsoft.com/v1/connections/$CONNECTION_ID")

if [ "$PATCH_CODE" -eq 200 ] || [ "$PATCH_CODE" -eq 204 ]; then
    echo "SUCCESS: Microsoft Fabric connection updated successfully."
else
    echo "FAILURE: Fabric API returned HTTP status $PATCH_CODE"
    exit 1
fi
