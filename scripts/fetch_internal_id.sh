#!/bin/bash
set -e
source db_env.sh
RESPONSE=$(curl -s -G -X GET \
  -H "Authorization: Bearer $DATABRICKS_TOKEN" \
  --data-urlencode "filter=displayName eq \"$TARGET_SPN_DISPLAY_NAME\"" \
  "$DATABRICKS_HOST/api/2.0/accounts/$ACCOUNT_ID/scim/v2/ServicePrincipals")

INTERNAL_ID=$(echo "$RESPONSE" | jq -r '.Resources[0].id // empty')
APP_ID=$(echo "$RESPONSE" | jq -r '.Resources[0].applicationId // empty')

if [ -z "$INTERNAL_ID" ] || [ "$INTERNAL_ID" == "null" ]; then
  echo "Error: SPN '$TARGET_SPN_DISPLAY_NAME' not found."
  exit 1
fi

echo "export DATABRICKS_INTERNAL_ID=$INTERNAL_ID" >> db_env.sh
echo "export TARGET_APPLICATION_ID=$APP_ID" >> db_env.sh
