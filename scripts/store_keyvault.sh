#!/bin/bash
set -e
# Use '.' instead of 'source' for better compatibility in Jenkins
[ -f db_env.sh ] && . ./db_env.sh

# Sanitize the name (replace spaces with dashes)
CLEAN_NAME=$(echo "$TARGET_SPN_DISPLAY_NAME" | tr ' ' '-')
SECRET_NAME="db-$CLEAN_NAME-secret"
ID_NAME="db-$CLEAN_NAME-id"

echo "-------------------------------------------------------"
echo "Updating Key Vault: $KEYVAULT_NAME"
echo "Secret Name: $SECRET_NAME"
echo "-------------------------------------------------------"

# 1. Store/Update the Application ID (usually stays the same, but good to keep in sync)
az keyvault secret set \
    --vault-name "$KEYVAULT_NAME" \
    --name "$ID_NAME" \
    --value "$TARGET_APPLICATION_ID" \
    --only-show-errors --output none

# 2. Store the NEW OAuth Secret and ensure it is ENABLED
# This creates a new 'Latest' version
az keyvault secret set \
    --vault-name "$KEYVAULT_NAME" \
    --name "$SECRET_NAME" \
    --value "$FINAL_OAUTH_SECRET" \
    --enabled true \
    --description "Rotated by Jenkins on $(date)" \
    --only-show-errors --output none

echo "New version stored and enabled."

# 3. Disable OLD versions
echo "Disabling older versions of $SECRET_NAME..."

# Get all version IDs for this secret
# We filter to find versions that are currently enabled and are NOT the one we just created
VERSIONS=$(az keyvault secret list-versions \
    --vault-name "$KEYVAULT_NAME" \
    --name "$SECRET_NAME" \
    --query "[?attributes.enabled==\`true\`].id" -o tsv)

# Get the ID of the version we just created (the latest one)
LATEST_ID=$(az keyvault secret show \
    --vault-name "$KEYVAULT_NAME" \
    --name "$SECRET_NAME" \
    --query "id" -o tsv)

# Loop through all enabled versions and disable them IF they are not the latest
for version_id in $VERSIONS; do
    if [ "$version_id" != "$LATEST_ID" ]; then
        echo "Disabling old version: $version_id"
        az keyvault secret set-attributes \
            --id "$version_id" \
            --enabled false \
            --only-show-errors --output none
    fi
done

echo "Key Vault update complete. Only the latest version is enabled."
echo "-------------------------------------------------------"
