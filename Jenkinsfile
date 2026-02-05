pipeline {
    agent any
 
    parameters {
        string(name: 'SPN_LIST', defaultValue: 'automation-spn', description: 'Enter a single SPN name, a comma-separated list, or "ALL"')
        // --- Discovery Parameters ---
        string(name: 'AZURE_RESOURCE_GROUP', defaultValue: 'rg-databricks-prod', description: 'Resource Group Name')
        string(name: 'AZURE_WORKSPACE_NAME', defaultValue: 'adb-prod-workspace', description: 'Workspace Name')
        string(name: 'SQL_WAREHOUSE_NAME', defaultValue: 'Serverless Starter Warehouse', description: 'SQL Warehouse Name')
    }
 
    environment {
        // --- CONSTANTS ---
        DATABRICKS_HOST       = 'https://accounts.azuredatabricks.net'
        FABRIC_API_URL        = "https://api.fabric.microsoft.com/v1"
 
        // --- CREDENTIALS ---
        KEYVAULT_NAME         = credentials('keyvault-name')
        ACCOUNT_ID            = credentials('databricks-account-id')
        AZURE_CLIENT_ID       = credentials('azure-client-id')
        AZURE_CLIENT_SECRET   = credentials('azure-client-secret')
        AZURE_TENANT_ID       = credentials('azure-tenant-id')
        AZURE_SUBSCRIPTION_ID = credentials('azure-subscription-id')
        // --- MAPPINGS ---
        AZURE_RESOURCE_GROUP  = "${params.AZURE_RESOURCE_GROUP}"
        AZURE_WORKSPACE_NAME  = "${params.AZURE_WORKSPACE_NAME}"
        TARGET_WAREHOUSE_NAME = "${params.SQL_WAREHOUSE_NAME}"
    }
 
    stages {
        stage('Initialize') {
            steps {
                sh 'chmod +x scripts/*.sh'
 
                // 1. Get Tokens
                sh './scripts/get_token.sh'          // Databricks
                sh './scripts/get_fabric_token.sh'   // Fabric
                // 2. Discover URLs (Finds Workspace URL + HTTP Path)
                sh './scripts/fetch_workspace_details.sh'
            }
        }
 
        stage('Process Service Principals') {
            steps {
                script {
                    def spns = params.SPN_LIST.split(',').collect { it.trim() }
 
                    spns.each { spn ->
                        stage("Rotate: ${spn}") {
                            withEnv(["TARGET_SPN_DISPLAY_NAME=${spn}"]) {
                                // 1. Fetch Internal ID
                                sh './scripts/fetch_internal_id.sh'
 
                                // 2. Create NEW Secret (Always create first)
                                sh './scripts/create_oauth_secret.sh'
 
                                // 3. Update Key Vault (New jobs get new secret)
                                sh './scripts/store_keyvault.sh'
 
                                // 4. Update Fabric Connection
                                // Updates the existing connection in "Manage Connections"
                                echo "Updating Fabric Authentication..."
                                sh './scripts/update_fabric_connection.sh'
 
                                // 5. Safe Cleanup
                                // Deletes only secrets older than the top 2 (Retention Policy)
                                echo "Running Safe Cleanup..."
                                sh './scripts/delete_old_secrets.sh'
                            }
                        }
                    }
                }
            }
        }
    }
 
    post {
        always {
            sh 'rm -f db_env.sh'
        }
    }
}
