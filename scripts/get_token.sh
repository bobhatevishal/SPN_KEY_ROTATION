#!/bin/bash
set -e
az login --service-principal --username "$AZURE_CLIENT_ID" --password "$AZURE_CLIENT_SECRET" --tenant "$AZURE_TENANT_ID" > /dev/null
DATABRICKS_TOKEN=$(az account get-access-token --resource 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d --query accessToken -o tsv)
echo "export DATABRICKS_TOKEN=$DATABRICKS_TOKEN" > db_env.sh
