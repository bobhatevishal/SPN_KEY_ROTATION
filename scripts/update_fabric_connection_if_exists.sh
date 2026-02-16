#!/bin/bash
set -e

# -------------------------------------------------------
# Load runtime variables
# -------------------------------------------------------
if [ -f db_env.sh ]; then
  . ./db_env.sh
else
  echo "ERROR: db_env.sh not found."
  exit 1
fi

# -------------------------------------------------------
# Validate required Fabric variables
# -------------------------------------------------------
if [ -z "$FABRIC_CLIENT_ID" ] || [ -z "$FABRIC_CLIENT_SECRET" ] || [ -z "$FABRIC_TENANT_ID" ]; then
  echo "ERROR: Fabric Service Principal variables are missing."
  echo "Ensure FABRIC_CLIENT_ID, FABRIC_CLIENT_SECRET, FABRIC_TENANT_ID are set in Jenkins."
  exit 1
fi

# -------------------------------------------------------
# Ensure Fabric CLI exists
# -------------------------------------------------------
if [ ! -f "fabricenv/bin/fab" ]; then
  echo "Fabric CLI not found. Installing locally..."
  python3 -m venv fabricenv
  . fabricenv/bin/activate
  pip install ms-fabric-cli==1.4.0 >/dev/null 2>&1
fi

FAB="fabricenv/bin/fab"

# -------------------------------------------------------
# Non-Interactive Service Principal Login
# -------------------------------------------------------
echo "Logging into Microsoft Fabric (Service Principal mode)..."

$FAB auth login \
  --service-principal \
  --client-id "$FABRIC_CLIENT_ID" \
  --client-secret "$FABRIC_CLIENT_SECRET" \
  --tenant "$FABRIC_TENANT_ID" \
  --no-browser >/dev/null

echo "Fabric login successful."

# Optional debug check
$FAB whoami || {
  echo "ERROR: Fabric authentication failed."
  exit 1
}

echo "-------------------------------------------------------"
echo "Updating Fabric Connection for SPN: $TARGET_SPN_DISPLAY_NAME"
echo "-------------------------------------------------------"

# -------------------------------------------------------
# Derive Connection Name
# -------------------------------------------------------
CLEAN_NAME=$(echo "$TARGET_SPN_DISPLAY_NAME" | tr ' ' '-')
TARGET_CONNECTION_DISPLAY_NAME="db-$CLEAN_NAME"

echo "Target Fabric Connection Name: $TARGET_CONNECTION_DISPLAY_NAME"

# -------------------------------------------------------
# Fetch Connection ID
# -------------------------------------------------------
RESPONSE=$($FAB api connections -A fabric)

CONNECTION_ID=$(echo "$RESPONSE" | jq -r --arg name "$TARGET_CONNECTION_DISPLAY_NAME" \
  '.text.value[]? | select(.displayName==$name) | .id')

if [ -z "$CONNECTION_ID" ]; then
  echo "No Fabric connection found for $TARGET_CONNECTION_DISPLAY_NAME"
  echo "Skipping Fabric update."
  exit 0
fi

echo "Fabric Connection ID: $CONNECTION_ID"

# -------------------------------------------------------
# Validate Secret
# -------------------------------------------------------
if [ -z "$FINAL_OAUTH_SECRET" ] || [ "$FINAL_OAUTH_SECRET" == "null" ]; then
  echo "ERROR: FINAL_OAUTH_SECRET is empty. Aborting."
  exit 1
fi

if [ -z "$TARGET_APPLICATION_ID" ]; then
  echo "ERROR: TARGET_APPLICATION_ID missing."
  exit 1
fi

# -------------------------------------------------------
# Generate Update Payload
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

echo "Updating Fabric connection credentials..."

# -------------------------------------------------------
# PATCH Connection
# -------------------------------------------------------
$FAB api connections/$CONNECTION_ID \
  -A fabric \
  -X patch \
  -i update.json >/dev/null

echo "-------------------------------------------------------"
echo "Fabric connection credentials rotated successfully."
echo "-------------------------------------------------------"
