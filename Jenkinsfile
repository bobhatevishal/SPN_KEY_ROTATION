pipeline {
  agent any

  parameters {
    string(name: 'SPN_LIST', defaultValue: 'automation-spn', description: 'Enter a single SPN name, a comma-separated list, or "ALL"')
  }

  environment {
    DATABRICKS_HOST   = 'https://accounts.azuredatabricks.net'
    KEYVAULT_NAME     = credentials('keyvault-name')
    ACCOUNT_ID        = credentials('databricks-account-id')
    
    AZURE_CLIENT_ID       = credentials('azure-client-id')
    AZURE_CLIENT_SECRET   = credentials('azure-client-secret')
    AZURE_TENANT_ID       = credentials('azure-tenant-id')
    AZURE_SUBSCRIPTION_ID = credentials('azure-subscription-id')
  }

  stages {
    stage('Initialize & Login') {
      steps {
        sh 'chmod +x scripts/*.sh'
        // Login once and get the token for the entire run
        sh './scripts/get_token.sh'
      }
    }

    stage('Process Service Principals') {
      steps {
        script {
          def spns = []
          
          if (params.SPN_LIST.toUpperCase() == 'ALL') {
            // OPTIONAL: Logic to fetch all 80 names from a file or API
            // For now, let's assume a pre-defined list or comma-sep input
            echo "Processing all SPNs..."
          } else {
            spns = params.SPN_LIST.split(',').collect { it.trim() }
          }

          for (spn in spns) {
            stage("SPN: ${spn}") {
              echo "Starting rotation for: ${spn}"
              
              withEnv(["TARGET_SPN_DISPLAY_NAME=${spn}"]) {
                // 1. Fetch ID and check if secrets exist
                sh './scripts/fetch_internal_id.sh'
                
                script {
                    // Read the export file to see if we need to delete
                    def hasSecrets = sh(script: "source db_env.sh && echo \$HAS_SECRETS", returnStdout: true).trim()
                    
                    if (hasSecrets.toInteger() > 0) {
                        echo "Secrets found (${hasSecrets}). Running deletion..."
                        sh './scripts/delete_old_secrets.sh'
                    } else {
                        echo "No secrets found. Skipping deletion."
                    }
                }

                // 2. Always create the new secret
                sh './scripts/create_oauth_secret.sh'
                sh './scripts/store_keyvault.sh'
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
