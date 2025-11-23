@Library('JenkinsSharedLibs') _

pipeline {
  agent any

  environment {
    REGISTRY     = "docker.io/${REGISTRY}"
    IMAGE_NAME   = "skycanary"
    STABLE_TAG   = "stable"
    LATEST_TAG   = "latest"
    NAMESPACE    = "skycanary"
    HEALTH_URL   = "http://localhost:8090/api/state"
    PATH         = "/usr/local/bin:${env.PATH}"
  }

  stages {

    stage('🧹 Clean Workspace') {
      steps { clean_ws() }
    }

    stage('📦 Checkout Code') {
      steps {
        echo "📥 Cloning Git Repository..."
        clone('https://github.com/gauravchile/SkyCanary.git', 'main')
      }
    }

    stage('🏗️ Build Docker Images') {
      steps {
        script {
          dir('app') {
            docker_build("${IMAGE_NAME}", "${STABLE_TAG}", "${REGISTRY}")
            docker_build("${IMAGE_NAME}", "${LATEST_TAG}", "${REGISTRY}")
          }
        }
      }
    }

    stage('📤 Push Docker Images') {
      steps {
        script {
          docker_push("${IMAGE_NAME}", "${STABLE_TAG}", "${REGISTRY}")
          docker_push("${IMAGE_NAME}", "${LATEST_TAG}", "${REGISTRY}")
        }
      }
    }

    stage('☸️ Deploy to Kubernetes') {
      steps {
        script {
          k8s_deploy('kubernetes/base', "${NAMESPACE}")
        }
      }
    }

    stage('🚦 Canary Rollout (25%)') {
      steps {
        echo "⚙️ Rolling out canary deployment to 25% traffic..."
        sh '''
          kubectl -n ${NAMESPACE} patch virtualservice skycanary-vs --type=json \
            -p='[{"op":"replace","path":"/spec/http/0/route/1/weight","value":25}]'
          echo "✅ Canary rollout set to 25% traffic."
        '''
      }
    }

    stage('🧠 Health Check') {
      steps {
        echo "🧩 Performing health check..."
        health_check("${HEALTH_URL}")
      }
    }

    stage('📊 Generate Reports') {
      steps {
        generate_reports('reports')
      }
    }
  }

  post {
    success {
      script {
        notify_slack('#devops', "✅ SkyCanary pipeline succeeded — image pushed & deployed.")
        notify_email('devops@skycanary.io', 'Build Success', "SkyCanary deployed successfully.")
        backup_configs()
      }
    }
    failure {
      script {
        notify_slack('#devops', "❌ SkyCanary pipeline failed. Rolling back...")
        rollback_deploy("${NAMESPACE}", "${IMAGE_NAME}")
      }
    }
  }
}
