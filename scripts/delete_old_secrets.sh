#!/bin/bash
set -e
source db_env.sh

echo "Checking for existing secrets for SPN: $TARGET_SPN_DISPLAY_NAME"

# 1. List existing secrets
LIST_RESPONSE=$(curl -s -X GET \
  -H "Authorization: Bearer $DATABRICKS_TOKEN" \
  "$DATABRICKS_HOST/api/2.0/accounts/$ACCOUNT_ID/servicePrincipals/$DATABRICKS_INTERNAL_ID/credentials/secrets")

# 2. Extract Secret IDs
# If no secrets exist, jq will return an empty string rather than an error
SECRET_IDS=$(echo "$LIST_RESPONSE" | jq -r '.secrets[].id // empty')

# 3. Conditional Deletion
if [ -z "$SECRET_IDS" ]; then
  echo "No existing secrets found for $TARGET_SPN_DISPLAY_NAME. Proceeding to creation..."
else
  echo "Found existing secrets. Cleaning up..."
  for SID in $SECRET_IDS; do
    echo "Deleting secret: $SID"
    curl -s -X DELETE \
      -H "Authorization: Bearer $DATABRICKS_TOKEN" \
      "$DATABRICKS_HOST/api/2.0/accounts/$ACCOUNT_ID/servicePrincipals/$DATABRICKS_INTERNAL_ID/credentials/secrets/$SID"
  done
  echo "Cleanup complete."
fi
