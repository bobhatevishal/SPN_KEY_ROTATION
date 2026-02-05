#!/bin/bash
set -e
[ -f db_env.sh ] && . ./db_env.sh

echo "Requesting OAuth secret for $TARGET_SPN_DISPLAY_NAME..."

# 1. Execute the API call
RESPONSE=$(curl -s -X POST \
  -H "Authorization: Bearer $DATABRICKS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"lifetime_seconds\": 31536000, \"comment\": \"Rotation for $TARGET_SPN_DISPLAY_NAME\"}" \
  "$DATABRICKS_HOST/api/2.0/accounts/$ACCOUNT_ID/servicePrincipals/$DATABRICKS_INTERNAL_ID/credentials/secrets")

# 2. Extract the secret and catch "null" or empty
OAUTH_SECRET_VALUE=$(echo "$RESPONSE" | jq -r '.secret // empty')

# 3. STRICT VALIDATION: If the value is empty or literally the word "null", fail the script
if [ -z "$OAUTH_SECRET_VALUE" ] || [ "$OAUTH_SECRET_VALUE" == "null" ]; then
  echo "FATAL ERROR: Databricks API did not return a valid secret."
  echo "API Response was: $RESPONSE"
  # Exit with code 1 so Jenkins knows this stage failed
  exit 1
fi

echo "Successfully generated new OAuth secret."
echo "export FINAL_OAUTH_SECRET=$OAUTH_SECRET_VALUE" >> db_env.sh
