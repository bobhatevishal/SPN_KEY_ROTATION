#!/bin/bash
set -e

# Load runtime variables
if [ -f db_env.sh ]; then
  . ./db_env.sh
else
  echo "ERROR: db_env.sh not found."
  exit 1
fi

# Ensure Fabric CLI exists
if [ ! -f "fabricenv/bin/fab" ]; then
  echo "Fabric CLI not found. Installing..."
  python3 -m venv fabricenv
  . fabricenv/bin/activate
  pip install ms-fabric-cli==1.4.0 >/dev/null 2>&1
fi

FAB="fabricenv/bin/fab"

echo "Logging into Fabric..."

$FAB auth login \
  -u "$FABRIC_CLIENT_ID" \
  -p "$FABRIC_CLIENT_SECRET" \
  --tenant "$FABRIC_TENANT_ID" >/dev/null 2>&1

echo "Fabric login done."

echo "-------------------------------------------------------"
echo "Updating Fabric Connection for SPN: $TARGET_SPN_DISPLAY_NAME"
echo "-------------------------------------------------------"

# 1️⃣ Derive Connection Name
CLEAN_NAME=$(echo "$TARGET_SPN_DISPLAY_NAME" | tr ' ' '-')
TARGET_CONNECTION_DISPLAY_NAME="db-$CLEAN_NAME"

echo "Target Fabric Connection Name: $TARGET_CONNECTION_DISPLAY_NAME"

# 2️⃣ Fetch Connection ID
RESPONSE=$($FAB api connections -A fabric)

CONNECTION_ID=$(echo "$RESPONSE" | jq -r --arg name "$TARGET_CONNECTION_DISPLAY_NAME" \
  '.text.value[]? | select(.displayName==$name) | .id')

if [ -z "$CONNECTION_ID" ]; then
  echo "No Fabric connection found for $TARGET_CONNECTION_DISPLAY_NAME"
  echo "Skipping Fabric update."
  exit 0
fi

echo "Fabric Connection ID found."

# 3️⃣ Validate Secret
if [ -z "$FINAL_OAUTH_SECRET" ] || [ "$FINAL_OAUTH_SECRET" == "null" ]; then
  echo "ERROR: FINAL_OAUTH_SECRET is empty. Aborting."
  exit 1
fi

# 4️⃣ Generate Update Payload
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

echo "Updating connection credentials..."

# 5️⃣ Patch
$FAB api connections/$CONNECTION_ID \
  -A fabric \
  -X patch \
  -i update.json >/dev/null 2>&1

echo "Fabric connection credentials rotated successfully."
echo "-------------------------------------------------------"

 
