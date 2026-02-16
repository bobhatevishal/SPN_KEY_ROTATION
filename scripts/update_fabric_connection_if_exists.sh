#!/bin/bash
set -e

echo "-------------------------------------------------------"
echo "Starting Fabric Connection Update Script"
echo "-------------------------------------------------------"

# -------------------------------------------------------
# 1️⃣ Load runtime variables
# -------------------------------------------------------
if [ -f db_env.sh ]; then
  . ./db_env.sh
else
  echo "ERROR: db_env.sh not found."
  exit 1
fi

# -------------------------------------------------------
# 2️⃣ Ensure jq is installed
# -------------------------------------------------------
if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is not installed."
  exit 1
fi

# -------------------------------------------------------
# 3️⃣ Ensure Fabric CLI exists
# -------------------------------------------------------
if [ ! -f "fabricenv/bin/fab" ]; then
  echo "Fabric CLI not found. Installing..."

  python3 -m venv fabricenv
  . fabricenv/bin/activate
  pipx install ms-fabric-cli==1.4.0 >/dev/null 2>&1
fi

FAB="fabricenv/bin/fab"

# -------------------------------------------------------
# 4️⃣ Login to Fabric (NON-INTERACTIVE)
# -------------------------------------------------------
echo "Logging into Microsoft Fabric..."

$FAB auth login \
  -u "ccb59224-dc2f-4bf4-94d2-ae6eb1765ae9" \
  -p "vm78Q~xWdUW4S6h4sRN9KDVZzGk.5CeQQ-gv8cvc" \
  --tenant "6fbff720-d89b-4675-b188-48491f24b460" \
  --no-browser >/dev/null 2>&1

if [ $? -ne 0 ]; then
  echo "ERROR: Fabric login failed."
  exit 1
fi

echo "Fabric login successful."
echo "-------------------------------------------------------"

# -------------------------------------------------------
# 5️⃣ Derive Connection Name
# -------------------------------------------------------
CLEAN_NAME=$(echo "$TARGET_SPN_DISPLAY_NAME" | tr ' ' '-')
TARGET_CONNECTION_DISPLAY_NAME="db-$CLEAN_NAME"

echo "Updating Fabric Connection for SPN: $TARGET_SPN_DISPLAY_NAME"
echo "Target Fabric Connection Name: $TARGET_CONNECTION_DISPLAY_NAME"

# -------------------------------------------------------
# 6️⃣ Fetch Connection ID
# -------------------------------------------------------
RESPONSE=$($FAB api connections -A fabric)

CONNECTION_ID=$(echo "$RESPONSE" | jq -r --arg name "$TARGET_CONNECTION_DISPLAY_NAME" \
  '.text.value[]? | select(.displayName==$name) | .id')

if [ -z "$CONNECTION_ID" ] || [ "$CONNECTION_ID" == "null" ]; then
  echo "No Fabric connection found for $TARGET_CONNECTION_DISPLAY_NAME"
  echo "Skipping Fabric update."
  exit 0
fi

echo "Fabric Connection ID found: $CONNECTION_ID"

# -------------------------------------------------------
# 7️⃣ Validate Secret
# -------------------------------------------------------
if [ -z "$FINAL_OAUTH_SECRET" ] || [ "$FINAL_OAUTH_SECRET" == "null" ]; then
  echo "ERROR: FINAL_OAUTH_SECRET is empty. Aborting."
  exit 1
fi

# -------------------------------------------------------
# 8️⃣ Generate Update Payload
# -------------------------------------------------------
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

echo "Payload generated."

# -------------------------------------------------------
# 9️⃣ Patch Connection
# -------------------------------------------------------
echo "Updating connection credentials..."

$FAB api connections/$CONNECTION_ID \
  -A fabric \
  -X patch \
  -i update.json >/dev/null 2>&1

if [ $? -ne 0 ]; then
  echo "ERROR: Failed to update Fabric connection."
  exit 1
fi

echo "Fabric connection credentials rotated successfully."
echo "-------------------------------------------------------"

# -------------------------------------------------------
# 🔟 Cleanup
# -------------------------------------------------------
rm -f update.json

echo "Script completed successfully."
echo "-------------------------------------------------------"
