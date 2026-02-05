#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# 1. Load environment variables (Internal ID, Token, Account ID, etc.)
# We use '.' for POSIX compliance in Jenkins environments
if [ -f db_env.sh ]; then
    . ./db_env.sh
else
    echo "ERROR: db_env.sh not found. Cannot proceed without credentials."
    exit 1
fi

echo "-------------------------------------------------------"
echo "Target SPN: $TARGET_SPN_DISPLAY_NAME"
echo "Internal ID: $DATABRICKS_INTERNAL_ID"
echo "-------------------------------------------------------"

# 2. Call the Databricks Account API to create a new OAuth Secret
# Reference: POST /api/2.0/accounts/{account_id}/servicePrincipals/{id}/credentials/secrets
RESPONSE=$(curl -s -X POST \
  -H "Authorization: Bearer $DATABRICKS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"lifetime_seconds\": 31536000, 
    \"comment\": \"Rotated via Jenkins for $TARGET_SPN_DISPLAY_NAME\"
  }" \
  "$DATABRICKS_HOST/api/2.0/accounts/$ACCOUNT_ID/servicePrincipals/$DATABRICKS_INTERNAL_ID/credentials/secrets")

# 3. Extract the secret value using jq
# The '// empty' ensures we don't get a literal "null" string from jq
OAUTH_SECRET_VALUE=$(echo "$RESPONSE" | jq -r '.secret // empty')

# 4. STRICT VALIDATION: The Gatekeeper
# This prevents the "null value" issue you encountered.
if [ -z "$OAUTH_SECRET_VALUE" ] || [ "$OAUTH_SECRET_VALUE" == "null" ]; then
    echo "CRITICAL FAILURE: Databricks API did not return a valid secret."
    echo "API Response Body: $RESPONSE"
    
    # Check for specific common error messages in the response
    ERROR_CODE=$(echo "$RESPONSE" | jq -r '.error_code // "UNKNOWN"')
    if [ "$ERROR_CODE" == "PERMISSION_DENIED" ]; then
        echo "Reason: The Admin SPN lacks 'Service Principal Manager' rights on this SPN."
    elif [ "$ERROR_CODE" == "NOT_FOUND" ]; then
        echo "Reason: The Service Principal ID might be incorrect for this Account ID."
    fi
    
    # Exit with code 1 to stop the Jenkins stage
    exit 1
fi

# 5. Success - Export the secret to our environment file for the next stage
echo "Successfully generated new OAuth secret."
echo "export FINAL_OAUTH_SECRET=$OAUTH_SECRET_VALUE" >> db_env.sh

# Mask the secret in the logs (optional, but good practice)
echo "Secret generated and saved to environment file."
echo "-------------------------------------------------------"

echo "Successfully generated new OAuth secret."
echo "export FINAL_OAUTH_SECRET=$OAUTH_SECRET_VALUE" >> db_env.sh
