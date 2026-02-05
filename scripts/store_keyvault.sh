#!/bin/bash
set -e
source db_env.sh
CLEAN_NAME=$(echo "$TARGET_SPN_DISPLAY_NAME" | tr ' ' '-')
az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "db-$CLEAN_NAME-id" --value "$TARGET_APPLICATION_ID" --only-show-errors
az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "db-$CLEAN_NAME-secret" --value "$FINAL_OAUTH_SECRET" --only-show-errors
