@Library('JenkinsSharedLibs') _

pipeline {
  agent any

  parameters {
    string(
      name: 'CANARY_PERCENT',
      defaultValue: '25',
      description: 'Percentage of traffic to route to canary deployment'
    )
  }

  environment {
    USER            = 'gauravchile'
    REGISTRY        = 'docker.io'
    IMAGE_NAME      = 'skycanary'
    IMAGE_REPO      = "${REGISTRY}/${USER}/${IMAGE_NAME}"
    IMAGE_TAG       = "build-${BUILD_NUMBER}"
    NAMESPACE       = 'skycanary'
    HEALTH_URL      = "http://localhost:8090/api/state"
    EMAIL_RECIPIENT = 'gauravchile07@gmail.com'
    PATH            = "/usr/local/bin:/usr/bin:/bin:/home/ubuntu/.local/bin:${PATH}"
  }

  options {
    timestamps()
    ansiColor('xterm')
  }

  stages {

    stage('🧹 Clean Workspace') {
      steps { clean_ws() }
    }

    stage('📦 Checkout Code') {
      steps {
        echo "📥 Cloning SkyCanary repository..."
        checkout scm
      }
    }

    stage('🏗️ Build Docker Image') {
      steps {
        script {
          dir('app') {
            docker_build(
              imageName: "${env.IMAGE_REPO}",
              imageTag: "${env.IMAGE_TAG}",
              noCache: true
            )
          }
        }
      }
    }

    stage('📤 Push Docker Image') {
      steps {
        script {
          docker_push(
            imageName: "${env.IMAGE_REPO}",
            imageTag: "${env.IMAGE_TAG}",
            credentials: 'dockerhub-creds',
            pushLatest: true
          )
        }
      }
    }

    stage('☸️ Deploy to Kubernetes') {
      steps {
        script {
          echo "🚀 Applying manifests to namespace ${env.NAMESPACE}..."
          k8s_deploy('kubernetes/base', env.NAMESPACE)
        }
      }
    }

    stage("🚦 Canary Rollout (${params.CANARY_PERCENT}%)") {
      steps {
        script {
          echo "⚙️ Adjusting canary traffic to ${params.CANARY_PERCENT}%..."
          sh """
            kubectl -n ${env.NAMESPACE} patch virtualservice skycanary-vs --type=json \
              -p='[{"op":"replace","path":"/spec/http/0/route/1/weight","value":${params.CANARY_PERCENT}}]'
            sleep 10
            kubectl get virtualservice skycanary-vs -n ${NAMESPACE} -o yaml
          """
        }
      }
    }

    stage('🧠 Health Check') {
      steps {
        script {
          echo "🔍 Performing health check on ${env.HEALTH_URL}"
          health_check(env.HEALTH_URL)
        }
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
        def summary = """
          <b>SkyCanary Pipeline Success</b><br>
          Build: <b>${BUILD_NUMBER}</b><br>
          Image: ${env.IMAGE_REPO}:${env.IMAGE_TAG}<br>
          Canary Traffic: ${params.CANARY_PERCENT}%<br>
        """
        notify_email(env.EMAIL_RECIPIENT, "✅ SkyCanary Success • Build ${BUILD_NUMBER}", summary)
        notify_slack('#devops', "✅ SkyCanary Build #${BUILD_NUMBER} deployed successfully (${params.CANARY_PERCENT}% canary).")
      }
    }

    unstable {
      notify_email(env.EMAIL_RECIPIENT, "⚠️ SkyCanary Warning", "Build marked UNSTABLE. Review scan or health results.")
      notify_slack('#devops', "⚠️ SkyCanary build unstable. Review Jenkins logs.")
    }

    failure {
      script {
        notify_email(env.EMAIL_RECIPIENT, "❌ SkyCanary Failed", "Pipeline failed. Check Jenkins logs and deployment status.")
        notify_slack('#devops', "❌ SkyCanary failed. Rolling back deployment...")
        rollback_deploy(env.NAMESPACE, env.IMAGE_NAME)
      }
    }

    always {
      archiveArtifacts artifacts: 'reports/**/*.{json,html,txt}', fingerprint: true
      cleanWs()
    }
  }
}
