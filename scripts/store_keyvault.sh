#!/bin/bash
set -e

# Load environment variables
[ -f db_env.sh ] && . ./db_env.sh

# Sanitize Name (Replace spaces with dashes)
CLEAN_NAME=$(echo "$TARGET_SPN_DISPLAY_NAME" | tr ' ' '-')
ID_NAME="db-$CLEAN_NAME-id"
SECRET_NAME="db-$CLEAN_NAME-secret"

echo "-------------------------------------------------------"
echo "Updating Key Vault: $KEYVAULT_NAME"
echo "Target Secret: $SECRET_NAME"
echo "-------------------------------------------------------"

# 1. Update the Application ID (Usually remains constant, but updated for consistency)
az keyvault secret set \
    --vault-name "$KEYVAULT_NAME" \
    --name "$ID_NAME" \
    --value "$TARGET_APPLICATION_ID" \
    --only-show-errors --output none

# 2. Store the NEW OAuth Secret
# We capture the URI/ID of the version we just created to keep it enabled
NEW_VERSION_ID=$(az keyvault secret set \
    --vault-name "$KEYVAULT_NAME" \
    --name "$SECRET_NAME" \
    --value "$FINAL_OAUTH_SECRET" \
    --query "id" -o tsv \
    --only-show-errors)

echo "New version created: $NEW_VERSION_ID"

# 3. Identify all PREVIOUS versions that are still ENABLED
# We look for all versions where enabled == true AND the ID is NOT our new one
OLD_VERSIONS=$(az keyvault secret list-versions \
    --vault-name "$KEYVAULT_NAME" \
    --name "$SECRET_NAME" \
    --query "[?attributes.enabled==\`true\` && id!='$NEW_VERSION_ID'].id" \
    -o tsv)

# 4. Disable the Old Versions
if [ -z "$OLD_VERSIONS" ]; then
    echo "No old enabled versions found."
else
    echo "Disabling older versions..."
    for version_id in $OLD_VERSIONS; do
        echo "Deactivating: $version_id"
        az keyvault secret set-attributes \
            --id "$version_id" \
            --enabled false \
            --only-show-errors --output none
    done
    echo "Old versions disabled successfully."
fi

echo "-------------------------------------------------------"
echo "Rotation Complete: Only the latest secret is active."
echo "export SECRET_NAME=$SECRET_NAME" >> db_env.sh
