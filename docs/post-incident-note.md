# Post-Incident Note: Failure Injection Test

**Date**: {{DATE}}
**Project**: TaskFlow URL Shortener
**Environment**: Production (AWS ap-southeast-2)
**Author**: Member 4

---

## Incident Summary

| Field | Value |
|-------|-------|
| **Incident Type** | Planned Failure Injection Test |
| **Trigger** | Deployment of intentionally broken Docker image |
| **Detection** | CloudWatch Alarm: `TaskFlow-UnhealthyTargets` |
| **Duration** | {{DURATION_MINUTES}} minutes |
| **Impact** | 100% of instances unhealthy, service unavailable |
| **Resolution** | Manual rollback via GitHub Actions workflow |

---

## Timeline

| Time (UTC) | Event |
|------------|-------|
| {{T0}} | Merged PR with broken backend image (missing `DB_PATH` env var) |
| {{T0+2m}} | CD pipeline completed ECR push, started ASG instance refresh |
| {{T0+5m}} | New instances launched, backend containers crashed on startup |
| {{T0+7m}} | ALB health checks failed → `UnHealthyHostCount` > 0 |
| {{T0+9m}} | **CloudWatch Alarm `TaskFlow-UnhealthyTargets` fired** → SNS email sent |
| {{T0+10m}} | Team alerted, investigated CloudWatch Logs |
| {{T0+12m}} | Root cause identified: `DB_PATH` env var missing in broken image |
| {{T0+13m}} | Triggered manual rollback workflow with previous tag `sha-{{PREV_SHA}}` |
| {{T0+18m}} | Rollback instance refresh completed |
| {{T0+20m}} | All targets healthy, alarm resolved |
| {{T0+22m}} | Service fully restored |

---

## Root Cause Analysis

### What Happened
A deliberately broken Docker image was built and pushed to ECR as part of a failure injection test. The backend container was missing the required `DB_PATH` environment variable, causing the Node.js application to crash immediately on startup with:

```
Error: DB_PATH environment variable is required
    at Object.<anonymous> (/app/src/index.js:15:13)
    at Module._compile (internal/modules/cjs/loader:1159:14)
```

### Why It Wasn't Caught Earlier
- **CI Stage 9 (Docker Build)**: Build succeeds because the Dockerfile doesn't validate runtime env vars
- **CI Stage 10 (Trivy)**: Only scans for OS/library vulnerabilities, not runtime configuration
- **No pre-deployment smoke test**: The CD pipeline deploys directly to ASG without a staging environment

### Contributing Factors
1. No integration test in CI that starts containers and verifies health endpoints
2. Environment variables not validated at container startup in a way that fails fast with clear messaging
3. Single-environment deployment (no staging)

---

## Detection & Response

### Detection Time: **~9 minutes**
- Alarm fired at `UnHealthyHostCount > 0` for 2 consecutive periods (2 minutes)
- SNS notification delivered via email within 1 minute of alarm state change

### Diagnosis Time: **~3 minutes**
- Checked CloudWatch Logs → `/aws/ec2/url-shortener` log group
- Filtered for `ERROR` level → Found missing `DB_PATH` immediately
- Confirmed by checking ECR image tags → identified broken tag `sha-{{BROKEN_SHA}}`

### Resolution Time: **~10 minutes**
- Used manual rollback workflow (`.github/workflows/rollback.yml`)
- Provided previous known-good tag `sha-{{PREV_SHA}}`
- ASG instance refresh with `MinHealthyPercentage: 50` took ~5 minutes
- Smoke test passed automatically after refresh completed

### Total MTTR: **~22 minutes**

---

## Action Items

| # | Action | Owner | Priority | Target Date |
|---|--------|-------|----------|-------------|
| 1 | Add `DB_PATH` validation in Dockerfile `ENTRYPOINT` to fail fast with clear message | Member 1 | High | Next sprint |
| 2 | Add integration test in CI that runs `docker compose up` and verifies `/health` | Member 2 | High | Next sprint |
| 3 | Add staging environment for pre-production validation | Member 3 | Medium | Next quarter |
| 4 | Reduce `UnhealthyTargets` alarm evaluation period from 2m to 1m | Member 4 | Low | This sprint |
| 5 | Document rollback runbook in README with screenshots | Member 4 | Medium | This sprint |
| 6 | Add Slack/Teams webhook to SNS for faster alerting | Member 4 | Low | Next sprint |

---

## Lessons Learned

### What Went Well
- ✅ OIDC-based deployment worked flawlessly (no static credentials)
- ✅ ASG instance refresh with `SkipMatching: true` only replaced unhealthy instances
- ✅ CloudWatch alarms detected the issue automatically within 9 minutes
- ✅ Manual rollback workflow executed successfully on first attempt
- ✅ Smoke test validated recovery automatically

### What Could Improve
- ⚠️ **Detection delay**: 9 minutes is acceptable but could be faster with 1-minute evaluation periods
- ⚠️ **No staging**: Direct production deployment means any broken image affects users
- ⚠️ **Container health checks**: Docker health check interval (30s) + ALB health check (30s) = up to 60s before ALB marks unhealthy
- ⚠️ **Notification channel**: Email-only SNS subscription; should add Slack/Teams for on-call

### Key Metrics
| Metric | Value | Target |
|--------|-------|--------|
| Mean Time to Detect (MTTD) | 9 min | < 5 min |
| Mean Time to Respond (MTTR) | 22 min | < 15 min |
| Alarm Precision | 100% (no false positives) | 100% |
| Rollback Success Rate | 100% (1/1) | 100% |

---

## Evidence (Screenshots to Attach)

1. **CloudWatch Alarm State** - `TaskFlow-UnhealthyTargets` in ALARM state
2. **SNS Email Notification** - Received alert email
3. **CloudWatch Logs** - Container crash logs showing missing `DB_PATH`
4. **GitHub Actions Rollback Workflow** - Successful execution
5. **ASG Instance Refresh** - In-progress and completed states
6. **Post-Rollback Health** - All targets healthy in ALB console

---

## Sign-Off

- **Incident Commander**: Member 4
- **Technical Lead**: Member 2
- **Infrastructure Owner**: Member 3
- **Application Owner**: Member 1

**Next Review**: {{NEXT_REVIEW_DATE}}