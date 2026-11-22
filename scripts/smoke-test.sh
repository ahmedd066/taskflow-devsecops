#!/bin/bash
#
# Smoke Test Script for TaskFlow URL Shortener
# Runs health checks against ALB after deployment
# Supports auto-rollback on failure
#
# Usage: ./smoke-test.sh <ALB_DNS> [PREVIOUS_IMAGE_TAG]
#
# Exit codes:
#   0 - Success
#   1 - Health check failed, rollback attempted
#   2 - Health check failed, no rollback possible

set -euo pipefail

# =============================================================================
# CONFIGURATION
# =============================================================================
ALB_DNS="${1:-}"
PREVIOUS_IMAGE_TAG="${2:-}"
MAX_RETRIES=10
RETRY_INTERVAL=10
HEALTH_ENDPOINT="/health"
FRONTEND_ENDPOINT="/"
TIMEOUT=5

# AWS Configuration (must match CD workflow)
AWS_REGION="ap-southeast-2"
AWS_ACCOUNT_ID="078852546033"
ASG_NAME="url-shortener-asg"
LAUNCH_TEMPLATE_ID="lt-014537a1cb74e6918"
OIDC_ROLE_ARN="arn:aws:iam::078852546033:role/github-actions-deploy"

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

error() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

check_health() {
  local url="$1"
  local name="$2"

  if curl -f -s --max-time "${TIMEOUT}" "${url}" >/dev/null 2>&1; then
    log "${name} health check PASSED (${url})"
    return 0
  else
    error "${name} health check FAILED (${url})"
    return 1
  fi
}

trigger_rollback() {
  local rollback_tag="$1"

  if [[ -z "${rollback_tag}" ]]; then
    error "No previous image tag provided for rollback"
    return 2
  fi

  log "Triggering rollback to tag: ${rollback_tag}"

  # Configure AWS credentials (assumes running in GitHub Actions with OIDC)
  # If running locally, this requires aws configure or credentials in env
  if ! aws sts get-caller-identity >/dev/null 2>&1; then
    error "AWS credentials not configured. Cannot trigger rollback."
    return 2
  fi

  # Get current launch template data
  LT_DATA=$(aws ec2 describe-launch-template-versions \
    --launch-template-id "${LAUNCH_TEMPLATE_ID}" \
    --versions '$Latest' \
    --query 'LaunchTemplateVersions[0].LaunchTemplateData' \
    --output json --region "${AWS_REGION}" 2>/dev/null)

  if [[ -z "${LT_DATA}" || "${LT_DATA}" == "null" ]]; then
    error "Failed to get launch template data"
    return 2
  fi

  # Update UserData with rollback tag
  CURRENT_USER_DATA=$(echo "${LT_DATA}" | jq -r '.UserData // ""' | base64 -d)
  NEW_USER_DATA=$(echo "${CURRENT_USER_DATA}" | sed "s/IMAGE_TAG=.*/IMAGE_TAG=${rollback_tag}/")

  if ! echo "${NEW_USER_DATA}" | grep -q "IMAGE_TAG="; then
    NEW_USER_DATA=$(echo "${NEW_USER_DATA}" | sed "/^# Derived values/a IMAGE_TAG=${rollback_tag}")
  fi

  ENCODED_USER_DATA=$(echo -n "${NEW_USER_DATA}" | base64 -w 0)

  # Create new launch template version with rollback tag
  NEW_VERSION=$(aws ec2 create-launch-template-version \
    --launch-template-id "${LAUNCH_TEMPLATE_ID}" \
    --source-version '$Latest' \
    --launch-template-data "{\"UserData\":\"${ENCODED_USER_DATA}\"}" \
    --query 'LaunchTemplateVersion.VersionNumber' \
    --output text --region "${AWS_REGION}" 2>/dev/null)

  if [[ -z "${NEW_VERSION}" ]]; then
    error "Failed to create launch template version for rollback"
    return 2
  fi

  log "Created rollback Launch Template version: ${NEW_VERSION}"

  # Start instance refresh with rollback
  REFRESH_ID=$(aws autoscaling start-instance-refresh \
    --auto-scaling-group-name "${ASG_NAME}" \
    --preferences '{"MinHealthyPercentage": 50, "InstanceWarmup": 300, "SkipMatching": true}' \
    --query 'InstanceRefreshId' \
    --output text --region "${AWS_REGION}" 2>/dev/null)

  if [[ -z "${REFRESH_ID}" ]]; then
    error "Failed to start instance refresh for rollback"
    return 2
  fi

  log "Started rollback instance refresh: ${REFRESH_ID}"

  # Wait for rollback to complete
  if aws autoscaling wait instance-refresh-complete \
    --auto-scaling-group-name "${ASG_NAME}" \
    --instance-refresh-ids "${REFRESH_ID}" \
    --region "${AWS_REGION}" 2>/dev/null; then
    log "Rollback completed successfully to tag: ${rollback_tag}"
    return 0
  else
    error "Rollback instance refresh failed or timed out"
    return 2
  fi
}

# =============================================================================
# MAIN
# =============================================================================
main() {
  if [[ -z "${ALB_DNS}" ]]; then
    error "Usage: $0 <ALB_DNS> [PREVIOUS_IMAGE_TAG]"
    error "Example: $0 taskflow-alb-123456789.ap-southeast-2.elb.amazonaws.com sha-abc1234"
    exit 2
  fi

  log "Starting smoke test against ALB: ${ALB_DNS}"
  log "Max retries: ${MAX_RETRIES}, Interval: ${RETRY_INTERVAL}s"

  local backend_url="http://${ALB_DNS}/api${HEALTH_ENDPOINT}"
  local frontend_url="http://${ALB_DNS}${FRONTEND_ENDPOINT}"

  # Try health checks with retries
  for attempt in $(seq 1 "${MAX_RETRIES}"); do
    log "Attempt ${attempt}/${MAX_RETRIES}..."

    local backend_ok=false
    local frontend_ok=false

    if check_health "${backend_url}" "Backend"; then
      backend_ok=true
    fi

    if check_health "${frontend_url}" "Frontend"; then
      frontend_ok=true
    fi

    if [[ "${backend_ok}" == "true" && "${frontend_ok}" == "true" ]]; then
      log "All smoke tests PASSED!"
      exit 0
    fi

    if [[ ${attempt} -lt ${MAX_RETRIES} ]]; then
      log "Waiting ${RETRY_INTERVAL}s before retry..."
      sleep "${RETRY_INTERVAL}"
    fi
  done

  # All retries exhausted
  error "Smoke test FAILED after ${MAX_RETRIES} attempts"

  # Attempt rollback if previous tag provided
  if [[ -n "${PREVIOUS_IMAGE_TAG}" ]]; then
    log "Attempting automatic rollback..."
    if trigger_rollback "${PREVIOUS_IMAGE_TAG}"; then
      log "Rollback successful"
      exit 1  # Deployment failed but rollback succeeded
    else
      error "Rollback FAILED"
      exit 1
    fi
  else
    error "No previous image tag provided. Manual rollback required."
    log "To rollback manually, run: $0 ${ALB_DNS} <previous-image-tag>"
    exit 1
  fi
}

main "$@"