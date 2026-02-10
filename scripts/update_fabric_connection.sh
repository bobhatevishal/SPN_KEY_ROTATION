#!/bin/bash
set -e
 
echo "=============================================="
echo " Microsoft Fabric - Databricks Secret Rotation"
echo "=============================================="
 
# Load environment variables from previous pipeline stage
source ./db_env.sh
 
# Required variables in db_env.sh:
# TENANT_ID
# CLIENT_ID
# CLIENT_SECRET
# FABRIC_CLIENT_ID
# FABRIC_CLIENT_SECRET
 
FABRIC_TOKEN=$(curl -s -X POST \
"https://login.microsoftonline.com/${TENANT_ID}/oauth2/v2.0/token" \
-H "Content-Type: application/x-www-form-urlencoded" \
-d "grant_type=client_credentials" \
-d "client_id=${FABRIC_CLIENT_ID}" \
-d "client_secret=${FABRIC_CLIENT_SECRET}" \
-d "scope=https://api.fabric.microsoft.com/.default" \
| jq -r '.access_token')
 
if [[ -z "$FABRIC_TOKEN" || "$FABRIC_TOKEN" == "null" ]]; then
  echo "❌ Failed to acquire Fabric API token"
  exit 1
fi
 
echo "✅ Fabric API Token acquired"
 
# Fetch all connections
echo "Fetching Fabric Connections..."
CONNECTIONS=$(curl -s \
-H "Authorization: Bearer ${FABRIC_TOKEN}" \
"https://api.fabric.microsoft.com/v1/connections")
 
COUNT=$(echo "$CONNECTIONS" | jq '.value | length')
echo "Found $COUNT total connections"
 
# Loop through Databricks connections
echo "$CONNECTIONS" | jq -c '.value[]' | while read CONN; do
 
  CONN_ID=$(echo "$CONN" | jq -r '.id')
  CONN_NAME=$(echo "$CONN" | jq -r '.displayName')
  PROVIDER=$(echo "$CONN" | jq -r '.provider')
 
  if [[ "$PROVIDER" == "databricks" || "$PROVIDER" == "azureDatabricks" ]]; then
 
    echo "----------------------------------------------"
    echo "Updating Databricks Connection: $CONN_NAME"
    echo "Connection ID: $CONN_ID"
 
    # Build PATCH payload
    UPDATE_PAYLOAD=$(jq -n \
      --arg tenant "$TENANT_ID" \
      --arg client "$CLIENT_ID" \
      --arg secret "$CLIENT_SECRET" \
      '{
        credentialDetails: {
          credentialType: "ServicePrincipal",
          tenantId: $tenant,
          clientId: $client,
          clientSecret: $secret,
          scope: "2ff814a6-3304-4ab8-85cb-cd0e6f879c1d/.default"
        }
      }')
 
    # PATCH update request
    RESPONSE=$(curl -s -X PATCH \
      -H "Authorization: Bearer ${FABRIC_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "$UPDATE_PAYLOAD" \
      "https://api.fabric.microsoft.com/v1/connections/${CONN_ID}")
 
    echo "✅ Rotated credentials for: $CONN_NAME"
 
  fi
done
 
echo "=============================================="
echo " Secret Rotation Completed Successfully"
echo "=============================================="
