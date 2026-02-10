#!/bin/bash
set -e
 
echo "=============================================="
echo " Microsoft Fabric - Databricks Secret Rotation"
echo "=============================================="
 
# Load environment variables from previous pipeline stage
source ./db_env.sh
 
# Required variables:
# TENANT_ID
# CLIENT_ID            (Databricks SPN Client ID)
# CLIENT_SECRET        (New Databricks Secret)
# FABRIC_CLIENT_ID     (Fabric Automation SPN)
# FABRIC_CLIENT_SECRET (Fabric SPN Secret)
 
echo "Acquiring Fabric API Token..."
 
FABRIC_RESPONSE=$(curl -s -X POST \
"https://login.microsoftonline.com/${TENANT_ID}/oauth2/v2.0/token" \
-H "Content-Type: application/x-www-form-urlencoded" \
-d "grant_type=client_credentials" \
-d "client_id=${FABRIC_CLIENT_ID}" \
-d "client_secret=${FABRIC_CLIENT_SECRET}" \
-d "scope=https://api.fabric.microsoft.com/.default")
 
# Debug output if token fails
if echo "$FABRIC_RESPONSE" | jq -e '.access_token' > /dev/null; then
  FABRIC_TOKEN=$(echo "$FABRIC_RESPONSE" | jq -r '.access_token')
  echo "✅ Fabric API Token acquired"
else
  echo "❌ Failed to acquire Fabric API token"
  echo "Azure Response:"
  echo "$FABRIC_RESPONSE"
  exit 1
fi
 
# Fetch Fabric connections
echo "Fetching Fabric Connections..."
 
CONNECTIONS=$(curl -s \
-H "Authorization: Bearer ${FABRIC_TOKEN}" \
"https://api.fabric.microsoft.com/v1/connections")
 
# Validate response structure
if ! echo "$CONNECTIONS" | jq -e '.value' > /dev/null; then
  echo "❌ Failed to retrieve Fabric connections"
  echo "$CONNECTIONS"
  exit 1
fi
 
COUNT=$(echo "$CONNECTIONS" | jq '.value | length')
echo "✅ Found $COUNT total connections"
 
# Loop through Databricks connections only
echo "$CONNECTIONS" | jq -c '.value[]' | while read CONN; do
 
  CONN_ID=$(echo "$CONN" | jq -r '.id')
  CONN_NAME=$(echo "$CONN" | jq -r '.displayName')
  PROVIDER=$(echo "$CONN" | jq -r '.provider')
 
  # Normalize provider check
  PROVIDER_LOWER=$(echo "$PROVIDER" | tr '[:upper:]' '[:lower:]')
 
  if [[ "$PROVIDER_LOWER" == *"databricks"* ]]; then
 
    echo "----------------------------------------------"
    echo "🔁 Rotating Secret for Databricks Connection"
    echo "Name: $CONN_NAME"
    echo "ID: $CONN_ID"
    echo "Provider: $PROVIDER"
 
    # Build PATCH payload
    UPDATE_PAYLOAD=$(jq -n \
      --arg tenant "$TENANT_ID" \
      --arg client "$CLIENT_ID" \
      --arg secret "$CLIENT_SECRET" \
      '{
        credentialDetails: {
          credentialType: "DatabricksClientCredentials",
          tenantId: $tenant,
          clientId: $client,
          clientSecret: $secret,
          scope: "2ff814a6-3304-4ab8-85cb-cd0e6f879c1d/.default"
        }
      }')
 
    echo "Updating credentials..."
 
    RESPONSE=$(curl -s -X PATCH \
      -H "Authorization: Bearer ${FABRIC_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "$UPDATE_PAYLOAD" \
      "https://api.fabric.microsoft.com/v1/connections/${CONN_ID}")
 
    # Validate PATCH result
    if echo "$RESPONSE" | jq -e '.id' > /dev/null; then
      echo "✅ Successfully rotated credentials for: $CONN_NAME"
    else
      echo "❌ Failed to update connection: $CONN_NAME"
      echo "Response:"
      echo "$RESPONSE"
    fi
 
  fi
done
 
echo "=============================================="
echo " ✅ Secret Rotation Completed Successfully"
echo "=============================================="
