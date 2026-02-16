#!/bin/bash
set -e

echo "-------------------------------------------------------"
echo "Starting Fabric Connection Sync"
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
# 2️⃣ Validate Required Azure SPN Variables
# -------------------------------------------------------
if [ -z "$AZURE_CLIENT_ID" ] || \
   [ -z "$AZURE_CLIENT_SECRET" ] || \
   [ -z "$AZURE_TENANT_ID" ]; then
  echo "ERROR: Azure SPN environment variables missing."
  exit 2
fi

# -------------------------------------------------------
# 3️⃣ Validate Required Variables
# -------------------------------------------------------
if [ -z "$TARGET_SPN_DISPLAY_NAME" ]; then
  echo "ERROR: TARGET_SPN_DISPLAY_NAME missing."
  exit 3
fi

if [ -z "$FINAL_OAUTH_SECRET" ]; then
  echo "ERROR: FINAL_OAUTH_SECRET missing."
  exit 4
fi

# -------------------------------------------------------
# 4️⃣ 🔐 HARDCODED GATEWAY ID
# -------------------------------------------------------
GATEWAY_ID="34377033-6f6f-433a-9a66-3095e996f65c"

# -------------------------------------------------------
# 5️⃣ Install Fabric CLI (if not exists)
# -------------------------------------------------------
if [ ! -d "fabricenv" ]; then
  echo "Installing Fabric CLI..."
  python3 -m venv fabricenv
  . fabricenv/bin/activate
  pip install ms-fabric-cli==1.4.0 >/dev/null 2>&1
fi

FAB="fabricenv/bin/fab"

# -------------------------------------------------------
# 6️⃣ Configure Fabric Auth (Service Principal)
# -------------------------------------------------------
export FABRIC_AUTH_TYPE="service-principal"
export FABRIC_CLIENT_ID="$AZURE_CLIENT_ID"
export FABRIC_CLIENT_SECRET="$AZURE_CLIENT_SECRET"
export FABRIC_TENANT_ID="$AZURE_TENANT_ID"

echo "Fabric authentication configured."

# -------------------------------------------------------
# 7️⃣ Derive Connection Name
# -------------------------------------------------------
CLEAN_NAME=$(echo "$TARGET_SPN_DISPLAY_NAME" | tr ' ' '-')
TARGET_CONNECTION_DISPLAY_NAME="db-$CLEAN_NAME"

echo "Target Fabric Connection: $TARGET_CONNECTION_DISPLAY_NAME"

# -------------------------------------------------------
# 8️⃣ Fetch Connection ID
# -------------------------------------------------------
RESPONSE=$($FAB api connections -A fabric)

CONNECTION_ID=$(echo "$RESPONSE" | jq -r \
  --arg name "$TARGET_CONNECTION_DISPLAY_NAME" \
  '.text.value[]? | select(.displayName==$name) | .id')

if [ -z "$CONNECTION_ID" ] || [ "$CONNECTION_ID" == "null" ]; then
  echo "No Fabric connection found. Skipping update."
  exit 0
fi

echo "Fabric Connection ID: $CONNECTION_ID"

# -------------------------------------------------------
# 9️⃣ Generate Update Payload
# -------------------------------------------------------
cat <<EOF > update.json
{
  "connectivityType": "VirtualNetworkGateway",
  "gatewayId": "$GATEWAY_ID",
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

echo "Patching Fabric connection..."

# -------------------------------------------------------
# 🔟 Update Connection
# -------------------------------------------------------
$FAB api connections/$CONNECTION_ID \
  -A fabric \
  -X patch \
  -i update.json

echo "Fabric connection rotated successfully."
echo "-------------------------------------------------------"

rm -f update.json
exit 0
