pipeline {
  agent any

  parameters {
    string(name: 'SPN_LIST', defaultValue: 'automation-spn', description: 'Enter a single SPN name, a comma-separated list, or "ALL"')
  }

  environment {
    // Azure & Databricks Config
    DATABRICKS_HOST       = 'https://accounts.azuredatabricks.net'
    KEYVAULT_NAME         = credentials('keyvault-name')
    ACCOUNT_ID            = credentials('databricks-account-id')
    
    // Service Principal for Jenkins execution
    AZURE_CLIENT_ID       = credentials('azure-client-id')
    AZURE_CLIENT_SECRET   = credentials('azure-client-secret')
    AZURE_TENANT_ID       = credentials('azure-tenant-id')
    AZURE_SUBSCRIPTION_ID = credentials('azure-subscription-id')

    // Fabric Configuration (Update this ID!)
    FABRIC_WORKSPACE_ID   = 'yo782d76e6-7830-4038-8613-894916a67b22' 
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
            echo "Processing all SPNs..."
            // Logic to fetch all names would go here
          } else {
            spns = params.SPN_LIST.split(',').collect { it.trim() }
          }

          spns.each { spn ->
            def currentSPN = spn
            
            stage("SPN: ${currentSPN}") {
              try {
                echo "Starting rotation for: ${currentSPN}"
                
                withEnv(["TARGET_SPN_DISPLAY_NAME=${currentSPN}"]) {
                  sh './scripts/fetch_internal_id.sh'
                  
                  script {
                      def hasSecrets = sh(script: ". ./db_env.sh && echo \$HAS_SECRETS", returnStdout: true).trim()
                      
                      if (hasSecrets && hasSecrets.toInteger() > 0) {
                          echo "Secrets found (${hasSecrets}). Running deletion..."
                          sh './scripts/delete_old_secrets.sh'
                      } else {
                          echo "No secrets found. Skipping deletion."
                      }

                      // 1. CREATE THE SECRET
                      sh './scripts/create_oauth_secret.sh'

                      // 2. STRICT NULL CHECK
                      def checkSecret = sh(
                          script: ". ./db_env.sh && echo \$FINAL_OAUTH_SECRET", 
                          returnStdout: true
                      ).trim()

                      if (!checkSecret || checkSecret == "null") {
                          error "FATAL: Secret for ${currentSPN} is NULL or empty. Aborting this SPN."
                      }
                      
                      // 3. UPDATE KEY VAULT (Single Source of Truth)
                      echo "Secret validated. Updating Key Vault..."
                      sh './scripts/store_keyvault.sh'

                      // 4. UPDATE MICROSOFT FABRIC (Conditional Sync)
                      echo "Key Vault updated. Syncing to Microsoft Fabric..."
                      
                      // Check if connection exists via API
                      def connectionCheck = sh(
                        script: """
                          export FABRIC_ACCESS_TOKEN=\$(az account get-access-token --resource "https://analysis.windows.net/powerbi/api" --query accessToken -o tsv)
                          
                          # Query Fabric API for the connection name
                          curl -s "https://api.powerbi.com/v1.0/myorg/groups/${env.FABRIC_WORKSPACE_ID}/connections" \
                            -H "Authorization: Bearer \$FABRIC_ACCESS_TOKEN" \
                            -H "Content-Type: application/json" | \
                            jq -r --arg name "db-${currentSPN}" '.value[]? | select(.name == \$name) | .id'
                        """,
                        returnStdout: true
                      ).trim()

                      // 4a. If Exists -> ROTATE
                      if (connectionCheck && connectionCheck != "null" && connectionCheck != "") {
                        echo "Connection exists (ID: ${connectionCheck}). Running ROTATION script..."
                        sh "./scripts/rotate_fabric_connection.sh"
                      } 
                      // 4b. If Not Exists -> CREATE
                      else {
                        echo "Connection does not exist. Running CREATION script..."
                        sh "./scripts/create_fabric_connection.sh"
                      }
                  }
                }
              } catch (Exception e) {
                echo "ERROR processing ${currentSPN}: ${e.getMessage()}"
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
      // Debug output before cleanup
      sh 'cat db_env.sh || true'
      sh 'rm -f db_env.sh'
    }
  }
}
