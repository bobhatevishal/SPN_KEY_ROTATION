#!/bin/bash
set -e
 
# Source environment (Ensure$ID_NAME and FINAL_OAUTH_SECRET are present)
source ./db_env.sh
 
# Fabric configuration
FABRIC_WORKSPACE_ID="${FABRIC_WORKSPACE_ID:-782d76e6-7830-4038-8613-894916a67b22}"
FABRIC_ACCESS_TOKEN="${FABRIC_ACCESS_TOKEN:-$(az account get-access-token --resource 'https://analysis.windows.net/powerbi/api' --query accessToken -o tsv)}"
CONNECTION_NAME="db-${TARGET_SPN_DISPLAY_NAME}"
BASE_URL="https://api.fabric.microsoft.com/v1/workspaces"
 
# Databricks Connection Details from UI
DATABRICKS_HOST="${DATABRICKS_HOST:-adb-7405609173671370.10.azuredatabricks.net}"
DATABRICKS_HTTP_PATH="${DATABRICKS_HTTP_PATH:-/sql/1.0/warehouses/559747c78f71249c}"
 
echo "=== CREATE Fabric Connection: ${CONNECTION_NAME} ==="
 
# Validation
if [[ -z "$FINAL_OAUTH_SECRET" || -z "$ID_NAME" ]]; then
    echo "ERROR:$ID_NAME or FINAL_OAUTH_SECRET is missing."
    exit 1
fi
 
HEADERS=(
    -H "Authorization: Bearer $FABRIC_ACCESS_TOKEN"
    -H "Content-Type: application/json"
)
 
# Payload matching the screenshot format
CREATE_BODY=$(jq -n \
    --arg name "$CONNECTION_NAME" \
    --arg host "$DATABRICKS_HOST" \
    --arg path "$DATABRICKS_HTTP_PATH" \
    --arg cid "$ID_NAME" \
    --arg secret "$FINAL_OAUTH_SECRET" \
    '{
        name: $name,
        connectionType: "AzureDatabricks",
        datasourceObject: {
            connectionDetails: {
                path: ("{\"host\":\"" + $host + "\",\"httpPath\":\"" + $path + "\"}")
            }
        },
        privacyLevel: "Organizational",
        credentialDetails: {
            credentialType: "DatabricksClientCredentials",
            databricksClientCredentials: {
                clientId: $cid,
                clientSecret: $secret
            },
            skipTestConnection: true
        }
    }')
 
curl -s -X POST "${BASE_URL}/groups/${FABRIC_WORKSPACE_ID}/connections" \
    "${HEADERS[@]}" -d "$CREATE_BODY" | jq .
 
echo "✓ Creation attempt finished for: $CONNECTION_NAME"
