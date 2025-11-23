pipeline {
  agent any

  environment {
    DOCKER_USER = "${REGISTRY}"
    APP_NAME    = "skycanary"
    STABLE_TAG  = "stable"
    LATEST_TAG  = "latest"
    NAMESPACE   = "skycanary"
    PATH        = "/usr/local/bin:${env.PATH}"
  }

  stages {

    stage('Checkout Code') {
      steps {
        echo "📦 Cloning repository..."
        git branch: 'main', url: 'https://github.com/gauravchile/SkyCanary.git'
      }
    }

    stage('Build Docker Images') {
      steps {
        echo "🐳 Building Docker images (stable & latest)..."
        sh '''
          docker build -t ${DOCKER_USER}/${APP_NAME}:${STABLE_TAG} \
                       -t ${DOCKER_USER}/${APP_NAME}:${LATEST_TAG} app/
        '''
      }
    }

    stage('Push to Docker Hub') {
      steps {
        echo "📤 Pushing both images to Docker Hub..."
        withCredentials([usernamePassword(credentialsId: 'dockerhub-creds', usernameVariable: 'USER', passwordVariable: 'PASS')]) {
          sh '''
            echo "$PASS" | docker login -u "$USER" --password-stdin
            docker push ${DOCKER_USER}/${APP_NAME}:${STABLE_TAG}
            docker push ${DOCKER_USER}/${APP_NAME}:${LATEST_TAG}
            docker logout
          '''
        }
      }
    }

    stage('Deploy to Kubernetes') {
      steps {
        echo "🚀 Deploying SkyCanary manifests..."
        sh '''
          set -e
          echo "📦 Applying namespace..."
          kubectl apply -f kubernetes/base/namespace.yaml

          echo "⏳ Waiting for namespace to initialize..."
          sleep 5

          echo "📦 Applying all Kubernetes manifests..."
          kubectl apply -f kubernetes/base/ --validate=false

          echo "🕒 Waiting for deployments to roll out..."
          kubectl rollout status deploy/skycanary-stable -n ${NAMESPACE} --timeout=180s || true
          kubectl rollout status deploy/skycanary-canary -n ${NAMESPACE} --timeout=180s || true
        '''
      }
    }

    stage('Canary Rollout') {
      steps {
        echo "⚙️ Rolling out canary deployment to 25% traffic..."
        sh '''
          kubectl -n ${NAMESPACE} patch virtualservice skycanary-vs --type=json \
            -p='[{"op":"replace","path":"/spec/http/0/route/1/weight","value":25}]'
          echo "✅ Canary rollout set to 25% traffic."
        '''
      }
    }

    stage('Health Check') {
      steps {
        echo "🧠 Performing post-deployment health check..."
        script {
          def response = sh(script: "curl -s -o /dev/null -w '%{http_code}' http://localhost:8090/api/state || true", returnStdout: true).trim()
          if (response == "200") {
            echo "✅ SkyCanary is live and healthy!"
          } else {
            error("❌ Health check failed! Got HTTP ${response}")
          }
        }
      }
    }
  }

  post {
    success {
      echo "🎉 Pipeline completed successfully — SkyCanary deployed and healthy!"
    }
    failure {
      echo "🚨 Pipeline failed. Check Jenkins logs for details."
    }
  }
}
