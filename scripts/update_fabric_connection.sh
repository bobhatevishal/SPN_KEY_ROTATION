#!/bin/bash
# Description: Updates Microsoft Fabric Cloud Connections with new OAuth secrets
set -e
 
# 1. Load the state from previous stages
# We need TARGET_APPLICATION_ID (The SPN Client ID) and FINAL_OAUTH_SECRET (The new secret)
if [ -f db_env.sh ]; then
    . ./db_env.sh
else
    echo "ERROR: db_env.sh not found. Cannot proceed."
    exit 1
fi
 
echo "-------------------------------------------------------"
echo "Fabric Integration: Updating Connection for $TARGET_SPN_DISPLAY_NAME"
echo "Target SPN Client ID: $TARGET_APPLICATION_ID"
echo "-------------------------------------------------------"
 
# 2. Check for active Azure Session
# We rely on the service principal login from previous stages.
if ! az account show > /dev/null 2>&1; then
    echo "ERROR: No active Azure session found. Please ensure 'az login' ran successfully."
    exit 1
fi
 
echo "Acquiring Fabric Access Token..."
# FIX 1: Use the correct Fabric API Resource URL
# The resource must be 'https://api.fabric.microsoft.com/' (trailing slash is important)
FABRIC_TOKEN=$(az account get-access-token \
    --resource "https://api.fabric.microsoft.com/" \
    --query accessToken -o tsv)
 
if [ -z "$FABRIC_TOKEN" ]; then
    echo "ERROR: Failed to acquire Fabric Access Token."
    exit 1
fi
 
# 3. Construct the Connection Name
# Logic: 'db-' + SPN name with spaces replaced by dashes (e.g., 'db-my-spn-name')
CLEAN_NAME=$(echo "$TARGET_SPN_DISPLAY_NAME" | tr ' ' '-')
FABRIC_CONN_NAME="db-$CLEAN_NAME"
 
echo "Searching for Fabric Connection Name: $FABRIC_CONN_NAME"
 
# 4. Find the Connection ID via Fabric API
# We list all connections and filter for the one matching our display name.
RESPONSE=$(curl -s -X GET \
  -H "Authorization: Bearer $FABRIC_TOKEN" \
  "https://api.fabric.microsoft.com/v1/connections")
 
# Extract the Fabric Connection ID (UUID)
CONNECTION_ID=$(echo "$RESPONSE" | jq -r ".value[] | select(.displayName==\"$FABRIC_CONN_NAME\") | .id // empty")
 
if [ -z "$CONNECTION_ID" ]; then
    echo "ERROR: Fabric Connection '$FABRIC_CONN_NAME' not found."
    echo "Action: Verify a connection with this EXACT name exists in Fabric 'Manage Connections'."
    exit 1
fi
 
echo "Found Fabric Connection ID: $CONNECTION_ID"
 
# 5. Patch the Connection with the NEW Secret
# FIX 2: Send the FULL credential details.
# Fabric requires Tenant ID + Client ID + Secret to validate the SPN.
echo "Updating credentials..."
 
# Use jq to safely construct the JSON payload
# We map the bash variables to JSON fields
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
 
# Execute the PATCH request
PATCH_RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X PATCH \
  -H "Authorization: Bearer $FABRIC_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \
  "https://api.fabric.microsoft.com/v1/connections/$CONNECTION_ID")
 
# 6. Validate the Result
HTTP_STATUS=$(echo "$PATCH_RESPONSE" | tail -n1 | cut -d':' -f2)
BODY=$(echo "$PATCH_RESPONSE" | sed '$d') # Remove the status line to show the body
 
if [ "$HTTP_STATUS" -eq 200 ]; then
    echo "SUCCESS: Microsoft Fabric connection updated successfully."
else
    echo "FAILURE: Fabric API returned HTTP status $HTTP_STATUS"
    echo "Response Body: $BODY"
    exit 1
fi
