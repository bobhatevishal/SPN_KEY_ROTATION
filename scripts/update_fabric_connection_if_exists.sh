#!/bin/bash
set -e

# Load runtime variables
if [ -f db_env.sh ]; then
  . ./db_env.sh
else
  echo "ERROR: db_env.sh not found."
  exit 1
fi

echo "-------------------------------------------------------"
echo "Updating Fabric Connection for SPN: $TARGET_SPN_DISPLAY_NAME"
echo "-------------------------------------------------------"

# 1️⃣ Derive Connection Display Name
CLEAN_NAME=$(echo "$TARGET_SPN_DISPLAY_NAME" | tr ' ' '-')
TARGET_CONNECTION_DISPLAY_NAME="db-$CLEAN_NAME"

echo "Target Fabric Connection Name: $TARGET_CONNECTION_DISPLAY_NAME"

# 2️⃣ Fetch Connection ID
CONNECTION_ID=$(fab api connections -A fabric | \
  jq -r --arg name "$TARGET_CONNECTION_DISPLAY_NAME" \
  '.text.value[] | select(.displayName==$name) | .id')

if [ -z "$CONNECTION_ID" ]; then
  echo "No Fabric connection found for $TARGET_CONNECTION_DISPLAY_NAME"
  echo "Skipping Fabric update."
  exit 0
fi

echo "Fabric Connection ID: $CONNECTION_ID"

# 3️⃣ Validate Secret Again (Safety)
if [ -z "$FINAL_OAUTH_SECRET" ] || [ "$FINAL_OAUTH_SECRET" == "null" ]; then
  echo "ERROR: FINAL_OAUTH_SECRET is empty. Aborting Fabric update."
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

echo "Update payload generated."

# 5️⃣ Patch the Connection
fab api connections/$CONNECTION_ID \
  -A fabric \
  -X patch \
  -i update.json

echo "Fabric connection updated successfully."
echo "-------------------------------------------------------"
