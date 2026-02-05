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
            stage("SPN: ${currentSPN}") {
              try {
                withEnv(["TARGET_SPN_DISPLAY_NAME=${currentSPN}"]) {
                  sh './scripts/fetch_internal_id.sh'
                  
                  // Logic for deletion as before...
                  
                  // 1. Run the creation script (this will now throw error if secret is null)
                  sh './scripts/create_oauth_secret.sh'
                  
                  // 2. EXTRA GATEKEEPER: Verify the variable is in db_env.sh before proceeding
                  script {
                      def checkSecret = sh(
                          script: ". ./db_env.sh && echo \$FINAL_OAUTH_SECRET", 
                          returnStdout: true
                      ).trim()

                      if (checkSecret == "" || checkSecret == "null") {
                          // This forces the 'catch' block to trigger
                          error "Pipeline Halted: The generated secret for ${currentSPN} is invalid/null."
                      }
                  }

                  // 3. Only runs if the check above passes
                  sh './scripts/store_keyvault.sh'
                }
              } catch (Exception e) {
                echo "FAILED: ${currentSPN}: ${e.getMessage()}"
                currentBuild.result = 'UNSTABLE'
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
