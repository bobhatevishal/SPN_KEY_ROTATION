#!/bin/bash
set -e
source db_env.sh

echo "Checking for existing secrets for SPN: $TARGET_SPN_DISPLAY_NAME ($DATABRICKS_INTERNAL_ID)"

# 1. List all existing secrets
LIST_RESPONSE=$(curl -s -X GET \
  -H "Authorization: Bearer $DATABRICKS_TOKEN" \
  "$DATABRICKS_HOST/api/2.0/accounts/$ACCOUNT_ID/servicePrincipals/$DATABRICKS_INTERNAL_ID/credentials/secrets")

# 2. Extract all Secret IDs
SECRET_IDS=$(echo "$LIST_RESPONSE" | jq -r '.secrets[].id // empty')

# 3. Delete each secret found
for SID in $SECRET_IDS; do
  echo "Deleting old secret: $SID"
  curl -s -X DELETE \
    -H "Authorization: Bearer $DATABRICKS_TOKEN" \
    "$DATABRICKS_HOST/api/2.0/accounts/$ACCOUNT_ID/servicePrincipals/$DATABRICKS_INTERNAL_ID/credentials/secrets/$SID"
done

echo "Cleanup complete."
