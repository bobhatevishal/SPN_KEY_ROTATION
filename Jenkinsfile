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

          // Loop through the list
          for (spn in spns) {
            // We use a variable so the catch block knows which one failed
            def currentSPN = spn 
            
            stage("SPN: ${currentSPN}") {
              try {
                echo "Starting rotation for: ${currentSPN}"
                
                withEnv(["TARGET_SPN_DISPLAY_NAME=${currentSPN}"]) {
                  // If fetch_internal_id.sh fails, it throws an exception here
                  sh './scripts/fetch_internal_id.sh'
                  
                  script {
                      def hasSecrets = sh(script: ". ./db_env.sh && echo \$HAS_SECRETS", returnStdout: true).trim()
                      if (hasSecrets.toInteger() > 0) {
                          echo "Secrets found (${hasSecrets}). Running deletion..."
                          sh './scripts/delete_old_secrets.sh'
                      } else {
                          echo "No secrets found. Skipping deletion."
                      }
                  }

                  sh './scripts/create_oauth_secret.sh'
                  sh './scripts/store_keyvault.sh'
                }
                echo "Successfully rotated: ${currentSPN}"

              } catch (Exception e) {
                // This is the fix: catch the error and keep going
                echo "FAILED to process ${currentSPN}: ${e.getMessage()}"
                currentBuild.result = 'UNSTABLE' 
                // The loop continues to the next 'spn' in 'spns'
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
