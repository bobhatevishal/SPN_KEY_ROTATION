#!/bin/bash
# Description: Updates Microsoft Fabric Cloud Connections with new OAuth secrets
set -e
 
# 1. Load the state from previous stages
# We need TARGET_APPLICATION_ID (Client ID) and FINAL_OAUTH_SECRET (New Secret)
if [ -f db_env.sh ]; then
    . ./db_env.sh
else
    echo "ERROR: db_env.sh not found. Cannot proceed."
    exit 1
fi
 
echo "-------------------------------------------------------"
echo "Fabric Integration: Updating Connection for $TARGET_SPN_DISPLAY_NAME"
echo "Target Client ID: $TARGET_APPLICATION_ID"
echo "-------------------------------------------------------"
 
# 2. Authenticate to Azure to get a Fabric API Token
# We use the Pipeline SPN (AZURE_CLIENT_ID) credentials from the Jenkins environment
echo "Logging in to Azure..."
az login --service-principal \
    --username "$AZURE_CLIENT_ID" \
    --password "$AZURE_CLIENT_SECRET" \
    --tenant "$AZURE_TENANT_ID" \
    --output none
 
echo "Acquiring Fabric Access Token..."
# NOTE: The resource scope here is specific to Fabric APIs
FABRIC_TOKEN=$(az account get-access-token \
    --resource "https://api.fabric.microsoft.com/.default" \
    --query accessToken -o tsv)
 
if [ -z "$FABRIC_TOKEN" ]; then
    echo "ERROR: Failed to acquire Fabric Access Token."
    exit 1
fi
 
# 3. Construct the Connection Name
# logic: 'db-' + SPN name with spaces replaced by dashes
CLEAN_NAME=$(echo "$TARGET_SPN_DISPLAY_NAME" | tr ' ' '-')
FABRIC_CONN_NAME="db-$CLEAN_NAME"
 
echo "Searching for Connection Name: $FABRIC_CONN_NAME"
 
# 4. Find the Connection ID
# We filter the list of connections to find the one matching our constructed name
RESPONSE=$(curl -s -X GET \
  -H "Authorization: Bearer $FABRIC_TOKEN" \
  "https://api.fabric.microsoft.com/v1/connections")
 
# Extract ID where displayName matches. Returns null if not found.
CONNECTION_ID=$(echo "$RESPONSE" | jq -r ".value[] | select(.displayName==\"$FABRIC_CONN_NAME\") | .id // empty")
 
if [ -z "$CONNECTION_ID" ]; then
    echo "ERROR: Fabric Connection '$FABRIC_CONN_NAME' not found."
    echo "Please ensure a connection exists in Fabric with this exact display name."
    exit 1
fi
 
echo "Found Connection ID: $CONNECTION_ID"
 
# 5. Patch the Connection with the NEW Secret
# IMPORTANT: We must send the full credential details, not just the secret.
echo "Updating credentials..."
 
# We use jq to construct the JSON payload safely to handle special characters in secrets
PAYLOAD=$(jq -n \
                  --arg tenant "$AZURE_TENANT_ID" \
                  --arg client "$TARGET_APPLICATION_ID" \
                  --arg secret "$FINAL_OAUTH_SECRET" \
                  '{
                    credentialDetails: {
                      useCallerCredentials: false,
                      credentials: {
                        credentialType: "ServicePrincipal",
                        tenantId: $tenant,
                        clientId: $client,
                        clientSecret: $secret
                      }
                    }
                  }')
 
PATCH_RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X PATCH \
  -H "Authorization: Bearer $FABRIC_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \
  "https://api.fabric.microsoft.com/v1/connections/$CONNECTION_ID")
 
# Extract HTTP status from the last line
HTTP_STATUS=$(echo "$PATCH_RESPONSE" | tail -n1 | cut -d':' -f2)
BODY=$(echo "$PATCH_RESPONSE" | sed '$d') # Remove the status line to get body
 
if [ "$HTTP_STATUS" -eq 200 ]; then
    echo "SUCCESS: Microsoft Fabric connection updated successfully."
else
    echo "FAILURE: Fabric API returned HTTP status $HTTP_STATUS"
    echo "Response Body: $BODY"
    exit 1
fi
