#!/bin/bash
set -e

# Source environment
source ./db_env.sh

# Fabric configuration
FABRIC_WORKSPACE_ID="${FABRIC_WORKSPACE_ID:-782d76e6-7830-4038-8613-894916a67b22}"
FABRIC_ACCESS_TOKEN="${FABRIC_ACCESS_TOKEN:-$(az account get-access-token --resource 'https://analysis.windows.net/powerbi/api' --query accessToken -o tsv)}"
CONNECTION_NAME="db-${TARGET_SPN_DISPLAY_NAME}"
BASE_URL="https://api.powerbi.com/v1.0/myorg"

echo "=== ROTATE Fabric Connection: ${CONNECTION_NAME} ==="

HEADERS=(
    -H "Authorization: Bearer $FABRIC_ACCESS_TOKEN"
    -H "Content-Type: application/json"
)

# 1. Find the Connection ID
CONNECTION_ID=$(curl -s "${BASE_URL}/groups/${FABRIC_WORKSPACE_ID}/connections" "${HEADERS[@]}" | \
    jq -r --arg name "$CONNECTION_NAME" '.value[]? | select(.name == $name) | .id')

if [[ -z "$CONNECTION_ID" || "$CONNECTION_ID" == "null" ]]; then
    echo "ERROR: Connection '$CONNECTION_NAME' not found. Cannot rotate."
    exit 1
fi

# 2. Update the Client Secret
echo "Updating secret for Connection ID: $CONNECTION_ID"
ROTATE_BODY=$(jq -n \
    --arg secret "$FINAL_OAUTH_SECRET" \
    '{
        credentialDetails: {
            credentialType: "DatabricksClientCredentials",
            databricksClientCredentials: {
                clientSecret: $secret
            }
        }
    }')

curl -s -X PATCH "${BASE_URL}/groups/${FABRIC_WORKSPACE_ID}/connections/${CONNECTION_ID}" \
    "${HEADERS[@]}" -d "$ROTATE_BODY" | jq .

echo "✓ Successfully ROTATED secret for: $CONNECTION_NAME"
