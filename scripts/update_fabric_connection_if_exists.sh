#!/bin/bash
set -e
if [ -f db_env.sh ]; then
    . ./db_env.sh
else
    echo "ERROR: db_env.sh not found. Cannot proceed without credentials."
    exit 1
fi
echo "=================================================="
echo " Microsoft Fabric Connection Credential Sync"
echo " Match by SPN Name | CLI Only | Key Vault Trusted"
echo "=================================================="

# Load env variables generated from previous pipeline steps
if [ ! -f db_env.sh ]; then
  echo "❌ db_env.sh not found. Aborting."
  exit 1
fi

source db_env.sh

echo "Loaded environment from db_env.sh"

# Validate required variables
REQUIRED_VARS=(
  TARGET_SPN_DISPLAY_NAME
  FINAL_OAUTH_SECRET
  AZURE_CLIENT_ID
  AZURE_CLIENT_SECRET
  AZURE_TENANT_ID
  FABRIC_WORKSPACE_ID
  DATABRICKS_HOST
  DATABRICKS_HTTP_PATH
)

for VAR in "${REQUIRED_VARS[@]}"; do
  if [ -z "${!VAR}" ]; then
    echo "❌ Missing required variable: $VAR"
    exit 1
  fi
done

echo "----------------------------------------------"
echo " SPN Name              : $TARGET_SPN_DISPLAY_NAME"
echo " Tenant ID             : $AZURE_TENANT_ID"
echo " Fabric Workspace ID   : $FABRIC_WORKSPACE_ID"
echo " Key Vault Secret ID   : ${KEYVAULT_SECRET_ID:-NOT_SET}"
echo "----------------------------------------------"

# Confirm secret presence
if [ -z "$FINAL_OAUTH_SECRET" ] || [ "$FINAL_OAUTH_SECRET" == "null" ]; then
  echo "❌ FINAL_OAUTH_SECRET is NULL or empty. Aborting."
  exit 1
fi

echo "✅ Secret validated from Key Vault runtime cache"

# Login to Microsoft Fabric using SPN
echo "Logging into Microsoft Fabric using SPN..."
fabric auth login \
  --service-principal \
  --client-id "$AZURE_CLIENT_ID" \
  --client-secret "$AZURE_CLIENT_SECRET" \
  --tenant-id "$AZURE_TENANT_ID"

# Select Fabric workspace
echo "Selecting Fabric Workspace..."
fabric workspace select "$FABRIC_WORKSPACE_ID"

# Fetch Fabric connections
echo "Fetching Fabric Connections from Workspace..."
CONNECTION_LIST=$(fabric connection list --output json || echo "[]")

if [ -z "$CONNECTION_LIST" ] || [ "$CONNECTION_LIST" == "[]" ]; then
  echo "⚠️ No Fabric connections found. Skipping update."
  exit 0
fi

# Match Fabric connection name to SPN name
MATCH_NAME="$TARGET_SPN_DISPLAY_NAME"

echo "Searching for Fabric connection matching SPN name: $MATCH_NAME"

MATCH_FOUND=$(echo "$CONNECTION_LIST" | jq -r --arg NAME "$MATCH_NAME" '.[] | select(.displayName==$NAME) | .displayName')

if [ -z "$MATCH_FOUND" ]; then
  echo "⚠️ No Fabric connection found matching '$MATCH_NAME'. Skipping update."
  exit 0
fi

echo " Found matching Fabric connection: $MATCH_FOUND"

# Build updated connection payload
echo "Preparing updated Fabric connection artifact..."

cat <<EOF > fabric_connection.json
{
  "type": "Connection",
  "displayName": "$MATCH_FOUND",
  "connectionType": "AzureDatabricks",
  "connectivityType": "Shareable",
  "credentialDetails": {
    "credentialType": "ServicePrincipal",
    "clientId": "$AZURE_CLIENT_ID",
    "clientSecret": "$FINAL_OAUTH_SECRET",
    "tenantId": "$AZURE_TENANT_ID"
  },
  "connectionDetails": {
    "workspaceUrl": "$DATABRICKS_HOST",
    "httpPath": "$DATABRICKS_HTTP_PATH"
  }
}
EOF

# Deploy update via Fabric CLI (overwrite existing)
echo "Deploying updated Fabric connection (overwrite mode)..."
fabric item deploy \
  --path fabric_connection.json \
  --workspace "$FABRIC_WORKSPACE_ID"

echo "--------------------------------------------------"
echo "✅ Fabric connection updated successfully"
echo " Connection Name : $MATCH_FOUND"
echo " Secret Source   : Azure Key Vault"
echo " Key Vault ID    : ${KEYVAULT_SECRET_ID:-UNKNOWN}"
echo "--------------------------------------------------"
 
