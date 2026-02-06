#!/bin/bash
# Description: Updates Microsoft Fabric Cloud Connections with Databricks Client Credentials
# Requirement: 'jq' must be installed on the Jenkins agent.
set -e

# 1. Load the state from previous stages
# Expected variables: TARGET_SPN_DISPLAY_NAME, TARGET_APPLICATION_ID, FINAL_OAUTH_SECRET
if [ -f db_env.sh ]; then
    . ./db_env.sh
else
    echo "ERROR: db_env.sh not found. Ensure previous stages exported credentials."
    exit 1
fi

echo "-------------------------------------------------------"
echo "Fabric Integration: Syncing Databricks Credentials"
echo "-------------------------------------------------------"

# 2. Authenticate for Microsoft Fabric (Power BI API)
FABRIC_TOKEN=$(az account get-access-token \
    --resource https://analysis.windows.net/powerbi/api \
    --query accessToken -o tsv)

# 3. Derive the Connection Name
CLEAN_NAME=$(echo "$TARGET_SPN_DISPLAY_NAME" | tr ' ' '-')
FABRIC_CONN_NAME="db-$CLEAN_NAME"

echo "Searching for Connection Name: $FABRIC_CONN_NAME"

# 4. Locate the Connection ID via Fabric API
RESPONSE=$(curl -s -X GET \
  -H "Authorization: Bearer $FABRIC_TOKEN" \
  "https://api.fabric.microsoft.com/v1/connections")

CONNECTION_ID=$(echo "$RESPONSE" | jq -r ".value[] | select(.displayName==\"$FABRIC_CONN_NAME\") | .id // empty")

if [ -z "$CONNECTION_ID" ]; then
    echo "ERROR: Fabric Connection '$FABRIC_CONN_NAME' not found."
    exit 1
fi

echo "Connection Found. ID: $CONNECTION_ID"

# 5. Construct the Lean Payload
# We remove 'connectionEncryption' and 'encryptionAlgorithm' to avoid 'InvalidInput' 400 errors.
# The API will preserve existing encryption settings if they are omitted.
# We ensure 'DatabricksClientCredentials' is used as the specific type.
PAYLOAD=$(cat <<EOF
{
  "credentialDetails": {
    "credentialType": "DatabricksClientCredentials",
    "credentials": {
      "servicePrincipalId": "$TARGET_APPLICATION_ID",
      "servicePrincipalKey": "$FINAL_OAUTH_SECRET"
    },
    "privacyLevel": "Private"
  }
}
EOF
)

# 6. Execute PATCH and Capture Error Body
DEBUG_FILE="fabric_api_error_log.json"
echo "Patching credentials in Fabric..."

PATCH_CODE=$(curl -s -w "%{http_code}" -X PATCH \
  -H "Authorization: Bearer $FABRIC_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \
  "https://api.fabric.microsoft.com/v1/connections/$CONNECTION_ID" -o "$DEBUG_FILE")

if [ "$PATCH_CODE" -eq 200 ] || [ "$PATCH_CODE" -eq 204 ]; then
    echo "SUCCESS: Microsoft Fabric connection updated successfully."
    rm -f "$DEBUG_FILE"
else    
    echo "FAILURE: Fabric API returned HTTP status $PATCH_CODE"
    echo "--- Detailed Error Body from Microsoft Fabric ---"
    if [ -f "$DEBUG_FILE" ]; then
        cat "$DEBUG_FILE"
        echo ""
    fi
    echo "------------------------------------------------"
    # Print the payload we sent (hiding the secret) for further debugging
    echo "Sent Payload (Secret Masked):"
    echo "$PAYLOAD" | jq '.credentialDetails.credentials.servicePrincipalKey = "***"'
    exit 1
fi
