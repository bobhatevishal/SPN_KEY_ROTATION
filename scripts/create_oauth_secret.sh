#!/bin/bash
set -e
source db_env.sh
JSON_PAYLOAD=$(cat <<EOF
{
  "lifetime_seconds": 31536000,
  "comment": "oauth-secret-for-$TARGET_SPN_DISPLAY_NAME"
}
EOF
)
RESPONSE=$(curl -s -X POST \
  -H "Authorization: Bearer $DATABRICKS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$JSON_PAYLOAD" \
  "$DATABRICKS_HOST/api/2.0/accounts/$ACCOUNT_ID/servicePrincipals/$DATABRICKS_INTERNAL_ID/credentials/secrets")

OAUTH_SECRET_VALUE=$(echo "$RESPONSE" | jq -r '.secret // empty')

if [ -z "$OAUTH_SECRET_VALUE" ] || [ "$OAUTH_SECRET_VALUE" == "null" ]; then
  echo "Failed to generate secret. Response: $RESPONSE"
  exit 1
fi

echo "export FINAL_OAUTH_SECRET=$OAUTH_SECRET_VALUE" >> db_env.sh
