# Rollback Runbook: TaskFlow URL Shortener

## Overview
This runbook describes how to rollback a failed deployment using the manual rollback workflow.

## When to Rollback
- Smoke test fails after CD deployment
- CloudWatch alarms fire (HighErrorRate, UnhealthyTargets)
- Manual verification shows broken functionality
- Performance degradation detected

## Prerequisites
- Access to GitHub repository: `ahmedd066/taskflow-devsecops`
- GitHub Actions workflow permissions (Write)
- Previous known-good image tag (format: `sha-<short-sha>` or `v<semver>`)

---

## Method 1: GitHub Actions Workflow (Recommended)

### Step 1: Identify Previous Good Tag
1. Go to AWS Console → ECR → Repositories → `url-shortener-backend`
2. Check "Images" tab for previous tags
3. Or check GitHub Actions → CD workflow runs → successful run → `IMAGE_TAG` output
4. Note the tag (e.g., `sha-a1b2c3d`)

### Step 2: Trigger Rollback Workflow
1. Go to **Actions** tab in GitHub
2. Select **"Manual Rollback"** workflow
3. Click **"Run workflow"** (top right)
4. Enter the previous good image tag:
   - `image_tag`: `sha-a1b2c3d` (or `v1.0.0`)
5. Click **"Run workflow"**

### Step 3: Monitor Rollback
1. Watch the workflow run (takes ~5-10 minutes)
2. Jobs executed:
   - Validate tag exists in both ECR repos
   - Create new Launch Template version
   - Start ASG instance refresh
   - Wait for completion
   - Run smoke test against ALB

### Step 4: Verify
- Workflow shows ✅ green
- Check ALB Target Group → All targets healthy
- Visit `http://taskflow-alb-1472473679.ap-southeast-2.elb.amazonaws.com` → Works

---

## Method 2: CLI Script (Emergency)

If GitHub Actions is unavailable:

```bash
# Prerequisites: AWS CLI configured with deploy role credentials
export AWS_REGION=ap-southeast-2
export ASG_NAME=url-shortener-asg
export LT_ID=lt-014537a1cb74e6918
export ROLLBACK_TAG=sha-a1b2c3d  # Previous good tag

# 1. Update Launch Template user data
CURRENT_UD=$(aws ec2 describe-launch-template-versions \
  --launch-template-id $LT_ID --versions '$Latest' \
  --query 'LaunchTemplateVersions[0].LaunchTemplateData.UserData' --output text)

# Decode, update IMAGE_TAG, re-encode
NEW_UD=$(echo $CURRENT_UD | base64 -d | sed "s/IMAGE_TAG=.*/IMAGE_TAG=$ROLLBACK_TAG/" | base64 -w 0)

# 2. Create new LT version
aws ec2 create-launch-template-version \
  --launch-template-id $LT_ID --source-version '$Latest' \
  --launch-template-data "{\"UserData\":\"$NEW_UD\"}"

# 3. Start instance refresh
REFRESH_ID=$(aws autoscaling start-instance-refresh \
  --auto-scaling-group-name $ASG_NAME \
  --preferences '{"MinHealthyPercentage":50,"InstanceWarmup":300,"SkipMatching":true}' \
  --query 'InstanceRefreshId' --output text)

# 4. Wait for completion
aws autoscaling wait instance-refresh-complete \
  --auto-scaling-group-name $ASG_NAME \
  --instance-refresh-ids $REFRESH_ID

# 5. Run smoke test
./scripts/smoke-test.sh taskflow-alb-1472473679.ap-southeast-2.elb.amazonaws.com
```

---

## Verification Checklist

After rollback, confirm:

- [ ] GitHub Actions workflow shows success
- [ ] ALB Target Group: All targets **healthy**
- [ ] CloudWatch Alarm `TaskFlow-UnhealthyTargets`: **OK** state
- [ ] Application loads at ALB DNS
- [ ] Backend `/health` returns 200
- [ ] Frontend `/` returns 200
- [ ] Create a short URL → redirects correctly

---

## Troubleshooting

| Issue | Resolution |
|-------|------------|
| "Image tag not found in ECR" | Tag may have been deleted (IMMUTABLE but can be deleted). Use `aws ecr describe-images` to list available tags. |
| Instance refresh stuck | Check ASG Activity History in console. May need to cancel and retry: `aws autoscaling cancel-instance-refresh` |
| Smoke test times out | Instances may still be warming up. Wait 2-3 minutes and re-run. |
| Rollback workflow fails at "Validate tag" | Ensure tag exists in **BOTH** backend AND frontend ECR repos with exact same tag. |

---

## Contacts

| Role | Contact |
|------|---------|
| DevOps Lead (Member 4) | @member4 |
| Backend Owner (Member 1) | @member1 |
| CI/CD Owner (Member 2) | @member2 |
| Infra Owner (Member 3) | @member3 |

---

## Related Documents
- [Post-Incident Note Template](post-incident-note.md)
- [CD Pipeline Workflow](../.github/workflows/cd.yml)
- [Smoke Test Script](../scripts/smoke-test.sh)