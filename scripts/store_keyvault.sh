#!/bin/bash
set -e

# Load credentials and variables
[ -f db_env.sh ] && . ./db_env.sh

# Sanitize names for Key Vault (dashes instead of spaces)
CLEAN_NAME=$(echo "$TARGET_SPN_DISPLAY_NAME" | tr ' ' '-')
SECRET_NAME="db-$CLEAN_NAME-secret"
ID_NAME="db-$CLEAN_NAME-id"

echo "-------------------------------------------------------"
echo "Key Vault: $KEYVAULT_NAME"
echo "Target Secret: $SECRET_NAME"
echo "-------------------------------------------------------"

# 1. Update the Application ID
# Using --attributes "enabled=true" instead of --enabled true
az keyvault secret set \
    --vault-name "$KEYVAULT_NAME" \
    --name "$ID_NAME" \
    --value "$TARGET_APPLICATION_ID" \
    --attributes "enabled=true" \
    --only-show-errors --output none

# 2. Push the NEW OAuth Secret
# We capture the unique Version ID to ensure we don't disable it later
NEW_VERSION_ID=$(az keyvault secret set \
    --vault-name "$KEYVAULT_NAME" \
    --name "$SECRET_NAME" \
    --value "$FINAL_OAUTH_SECRET" \
    --attributes "enabled=true" \
    --query "id" -o tsv \
    --only-show-errors)

echo "Success: Stored new version -> $NEW_VERSION_ID"

# 3. Identify all PREVIOUS versions that are still ENABLED
# Note: We use backticks to escape 'true' in the JMESPath query
OLD_VERSIONS=$(az keyvault secret list-versions \
    --vault-name "$KEYVAULT_NAME" \
    --name "$SECRET_NAME" \
    --query "[?attributes.enabled==\`true\` && id!='$NEW_VERSION_ID'].id" \
    -o tsv)

# 4. Disable the old versions
if [ -z "$OLD_VERSIONS" ]; then
    echo "No old enabled versions found to disable."
else
    echo "Disabling older versions..."
    for version_id in $OLD_VERSIONS; do
        echo "Processing: $version_id"
        # Explicitly turn off the enabled flag
        az keyvault secret set-attributes \
            --id "$version_id" \
            --enabled false \
            --only-show-errors --output none
    done
    echo "Cleanup complete."
fi

echo "-------------------------------------------------------"
