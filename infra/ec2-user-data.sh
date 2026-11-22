#!/bin/bash
#
# EC2 User Data Script for TaskFlow URL Shortener
# Runs on instance boot via Launch Template
# Pulls Docker images from ECR and starts the application stack
#
# IMAGE_TAG is injected by CD pipeline when creating new Launch Template version
# Do not set a default value — ECR uses IMMUTABLE tags, so each deploy must use a unique tag (git SHA)

set -euo pipefail

# =============================================================================
# CONFIGURATION - Member 3: Update these values before creating ASG
# =============================================================================
AWS_REGION="ap-southeast-2"
AWS_ACCOUNT_ID="078852546033"
ECR_BACKEND_REPO="url-shortener-backend"
ECR_FRONTEND_REPO="url-shortener-frontend"
# IMAGE_TAG is provided at runtime via Launch Template user data (no default)
# Expected format: sha-<git-short-sha> or v<semver>

# Derived values (IMAGE_TAG will be set at runtime)
ECR_BACKEND_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_BACKEND_REPO}"
ECR_FRONTEND_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_FRONTEND_REPO}"
COMPOSE_FILE="/opt/taskflow/docker-compose.yml"
ENV_FILE="/opt/taskflow/.env"

# =============================================================================
# LOGGING SETUP
# =============================================================================
exec > >(tee /var/log/taskflow-userdata.log | logger -t taskflow-userdata -s 2>/dev/console) 2>&1
echo "=== TaskFlow User Data Started at $(date) ==="

# =============================================================================
# INSTALL DEPENDENCIES
# =============================================================================
echo "Installing Docker, Docker Compose, AWS CLI v2, curl..."
dnf update -y
dnf install -y docker jq unzip curl

# Install Docker Compose v2 (plugin)
mkdir -p /usr/local/lib/docker/cli-plugins
curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64" \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# Start and enable Docker
systemctl enable --now docker
usermod -aG docker ec2-user

# Install AWS CLI v2 (for ECR login)
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip
./aws/install
rm -rf aws awscliv2.zip

# Install CloudWatch Agent (for memory metrics + logs)
dnf install -y amazon-cloudwatch-agent

echo "Dependencies installed."

# =============================================================================
# VALIDATE REQUIRED VARIABLES
# =============================================================================
if [[ -z "${IMAGE_TAG:-}" ]]; then
  echo "ERROR: IMAGE_TAG environment variable not set."
  echo "CD pipeline must inject IMAGE_TAG when creating Launch Template version."
  exit 1
fi
echo "Using image tag: ${IMAGE_TAG}"

# =============================================================================
# CREATE APPLICATION DIRECTORY
# =============================================================================
mkdir -p /opt/taskflow
cd /opt/taskflow

# =============================================================================
# WRITE DOCKER COMPOSE FILE
# =============================================================================
cat > "${COMPOSE_FILE}" <<'COMPOSE_EOF'
services:
  backend:
    image: ${ECR_BACKEND_URI}:${IMAGE_TAG}
    container_name: url-shortener-backend
    restart: unless-stopped
    environment:
      - PORT=3000
      - NODE_ENV=production
      - DB_PATH=/app/data/urls.db
    volumes:
      - urlshortener_data:/app/data
    healthcheck:
      test: ["CMD", "node", "-e", "require('http').get('http://localhost:3000/health', (res) => { if (res.statusCode !== 200) process.exit(1) }).on('error', () => process.exit(1))"]
      interval: 30s
      timeout: 3s
      retries: 3
      start_period: 10s
    logging:
      driver: awslogs
      options:
        awslogs-region: ${AWS_REGION}
        awslogs-group: /aws/ec2/url-shortener
        awslogs-stream: backend-${HOSTNAME}

  frontend:
    image: ${ECR_FRONTEND_URI}:${IMAGE_TAG}
    container_name: url-shortener-frontend
    restart: unless-stopped
    ports:
      - "8080:8080"
    depends_on:
      backend:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:8080/"]
      interval: 30s
      timeout: 3s
      retries: 3
      start_period: 10s
    logging:
      driver: awslogs
      options:
        awslogs-region: ${AWS_REGION}
        awslogs-group: /aws/ec2/url-shortener
        awslogs-stream: frontend-${HOSTNAME}

networks:
  default:
    name: urlshortener-net

volumes:
  urlshortener_data:
    driver: local
COMPOSE_EOF

echo "Docker Compose file written to ${COMPOSE_FILE}"

# =============================================================================
# WRITE ENV FILE (for docker compose variable substitution)
# =============================================================================
cat > "${ENV_FILE}" <<ENV_EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
ECR_BACKEND_URI=${ECR_BACKEND_URI}
ECR_FRONTEND_URI=${ECR_FRONTEND_URI}
IMAGE_TAG=${IMAGE_TAG}
ENV_EOF

echo "Environment file written to ${ENV_FILE}"

# =============================================================================
# CONFIGURE CLOUDWATCH AGENT
# =============================================================================
# Note: EC2 instance role (TaskFlow-EC2-SSM-Role) must have permissions:
# - logs:CreateLogGroup, logs:CreateLogStream, logs:PutLogEvents (for awslogs driver + CW Agent)
# - ssm:GetParameter (if using SSM for config)
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'CW_EOF'
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/taskflow-userdata.log",
            "log_group_name": "/aws/ec2/url-shortener",
            "log_stream_name": "userdata-{instance_id}"
          }
        ]
      }
    }
  },
  "metrics": {
    "namespace": "TaskFlow/EC2",
    "metrics_collected": {
      "cpu": {
        "measurement": ["cpu_usage_idle", "cpu_usage_user", "cpu_usage_system"],
        "metrics_collection_interval": 60,
        "resources": ["*"]
      },
      "mem": {
        "measurement": ["mem_used_percent", "mem_available", "mem_total"],
        "metrics_collection_interval": 60,
        "resources": ["*"]
      },
      "disk": {
        "measurement": ["disk_used_percent", "disk_free", "disk_total"],
        "metrics_collection_interval": 60,
        "resources": ["*"]
      }
    }
  }
}
CW_EOF

# Ensure log group exists (awslogs driver will create streams, but group must exist)
aws logs create-log-group --log-group-name /aws/ec2/url-shortener --region "${AWS_REGION}" 2>/dev/null || true

# Start CloudWatch Agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s

echo "CloudWatch Agent configured and started. Log group ensured."

# =============================================================================
# ECR LOGIN AND PULL IMAGES
# =============================================================================
echo "Logging in to ECR..."
aws ecr get-login-password --region "${AWS_REGION}" | \
  docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

echo "Pulling Docker images (tag: ${IMAGE_TAG})..."
if ! docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" pull; then
  echo "ERROR: Failed to pull Docker images. Check ECR permissions and image tag."
  exit 1
fi

# =============================================================================
# START APPLICATION STACK
# =============================================================================
echo "Starting application stack..."
if ! docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" up -d; then
  echo "ERROR: Failed to start containers."
  docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" logs
  exit 1
fi

# =============================================================================
# WAIT FOR HEALTH CHECKS
# =============================================================================
echo "Waiting for services to become healthy..."
for i in $(seq 1 30); do
  BACKEND_HEALTHY=$(docker inspect --format='{{.State.Health.Status}}' url-shortener-backend 2>/dev/null || echo "starting")
  FRONTEND_HEALTHY=$(docker inspect --format='{{.State.Health.Status}}' url-shortener-frontend 2>/dev/null || echo "starting")

  if [[ "${BACKEND_HEALTHY}" == "healthy" && "${FRONTEND_HEALTHY}" == "healthy" ]]; then
    echo "All services healthy."
    break
  fi

  if [[ $i -eq 30 ]]; then
    echo "ERROR: Services did not become healthy in time."
    docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" logs
    exit 1
  fi

  sleep 5
done

# =============================================================================
# VERIFY ENDPOINTS
# =============================================================================
echo "Verifying endpoints..."
curl -f http://localhost:3000/health && echo "Backend health OK"
curl -f http://localhost:8080/ && echo "Frontend OK"

echo "=== TaskFlow User Data Completed Successfully at $(date) ==="