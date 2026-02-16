#!/bin/bash
set -e

echo "-------------------------------------------------------"
echo "Starting Fabric Connection Secret Update"
echo "-------------------------------------------------------"

# Load runtime variables
if [ -f db_env.sh ]; then
  . ./db_env.sh
else
  echo "ERROR: db_env.sh not found."
  exit 1
fi

# Validate required values
if [ -z "$TARGET_APPLICATION_ID" ]; then
  echo "ERROR: TARGET_APPLICATION_ID missing."
  exit 2
fi

if [ -z "$FINAL_OAUTH_SECRET" ]; then
  echo "ERROR: FINAL_OAUTH_SECRET missing."
  exit 3
fi

if [ -z "$TARGET_SPN_DISPLAY_NAME" ]; then
  echo "ERROR: TARGET_SPN_DISPLAY_NAME missing."
  exit 4
fi

# Hardcoded Gateway ID (your confirmed working one)
GATEWAY_ID="34377033-6f6f-433a-9a66-3095e996f65c"

# Install Fabric CLI if not present
if [ ! -d "fabricenv" ]; then
  echo "Installing Fabric CLI..."
  python3 -m venv fabricenv
  . fabricenv/bin/activate
  pip install ms-fabric-cli==1.4.0 >/dev/null 2>&1
fi

FAB="fabricenv/bin/fab"

# Activate virtual environment
. fabricenv/bin/activate

# Login using Service Principal (IMPORTANT – do not rely only on env vars)
echo "Logging into Fabric..."
$FAB auth login \
  -u "$AZURE_CLIENT_ID" \
  -p "$AZURE_CLIENT_SECRET" \
  --tenant "$AZURE_TENANT_ID"

echo "Fabric login successful."

# Build connection name
CLEAN_NAME=$(echo "$TARGET_SPN_DISPLAY_NAME" | tr ' ' '-')
TARGET_CONNECTION_DISPLAY_NAME="db-$CLEAN_NAME"

echo "Target connection: $TARGET_CONNECTION_DISPLAY_NAME"

# Fetch connection ID
RESPONSE=$($FAB api connections -A fabric)

CONNECTION_ID=$(echo "$RESPONSE" | jq -r \
  --arg name "$TARGET_CONNECTION_DISPLAY_NAME" \
  '.text.value[]? | select(.displayName==$name) | .id')

if [ -z "$CONNECTION_ID" ] || [ "$CONNECTION_ID" == "null" ]; then
  echo "No Fabric connection found. Skipping update."
  exit 0
fi

echo "Connection ID: $CONNECTION_ID"

# Create update payload
cat <<EOF > update.json
{
  "connectivityType": "VirtualNetworkGateway",
  "displayName": "$TARGET_CONNECTION_DISPLAY_NAME",
  "privacyLevel": "Private",
  "credentialDetails": {
    "singleSignOnType": "None",
    "credentials": {
      "credentialType": "Basic",
      "username": "$TARGET_APPLICATION_ID",
      "password": "$FINAL_OAUTH_SECRET"
    }
  }
}
EOF

echo "Updating Fabric connection secret..."

$FAB api connections/$CONNECTION_ID \
  -A fabric \
  -X patch \
  -i update.json

echo "Secret rotation completed successfully."
echo "-------------------------------------------------------"

rm -f update.json
exit 0
