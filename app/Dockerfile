# Multi-version Dockerfile for SkyCanary (supports stable and canary builds)

FROM python:3.11-slim

# Build argument for app version
ARG VERSION=stable
ENV APP_VERSION=${VERSION}

# Environment variables
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV APP_NAME=skycanary
ENV USE_K8S=0
ENV PORT=8090

WORKDIR /opt/app

# Install system dependencies
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
    curl build-essential && \
    rm -rf /var/lib/apt/lists/*

# Copy app source
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# Healthcheck
HEALTHCHECK --interval=30s --timeout=5s --retries=3 CMD curl -f http://localhost:${PORT}/api/state || exit 1

# Expose port
EXPOSE ${PORT}

# Version label for easy identification
RUN echo "🔧 Building SkyCanary version: ${APP_VERSION}"

# Entry point
CMD ["python", "app.py"]
