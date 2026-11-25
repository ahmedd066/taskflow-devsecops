# taskflow-devsecops

A URL Shortener application deployed on AWS with a 12-stage DevSecOps CI/CD pipeline, containerized with Docker, and running behind an Application Load Balancer with Auto Scaling.

## Project Structure

- `backend/` — Node.js/Express API with SQLite database and Jest unit tests
- `frontend/` — Nginx static frontend
- `infra/ec2-user-data.sh` — EC2 startup script that pulls images from ECR and starts Docker Compose
- `scripts/build-test.sh` — Local build, test, and stack startup script
- `scripts/smoke-test.sh` — Post-deployment smoke test with auto-rollback
- `.github/workflows/ci.yml` — CI security gates (stages 1-10)
- `.github/workflows/cd.yml` — CD deployment pipeline (stages 11-12)
- `.github/workflows/rollback.yml` — Manual rollback workflow
- `docs/` — Post-incident note, rollback runbook and Short Findings Report

## CI and Security Checks

Pull requests to `main` run the ordered security workflow in `.github/workflows/ci.yml`. Configure these repository settings before expecting all checks to pass:

- Actions secrets: `SONAR_TOKEN` and `SNYK_TOKEN`.
- Actions variables: `SONAR_ORGANIZATION` and `SONAR_PROJECT_KEY`.
- For an organization-owned repository, add the Gitleaks license as the `GITLEAKS_LICENSE` Actions secret.
- Branch protection for `main`: require pull requests, at least one approval, and the workflow's successful status checks.
- Dependabot version updates are configured in `.github/dependabot.yml`.

The workflow's first stage is the Git push or pull request event (not a separate job). Gitleaks scans full Git history; its job is shown as stage 2. AWS OIDC is used by the deployment workflow and must be coordinated with the AWS role owner; this CI workflow does not deploy or require AWS credentials.

Pipeline stages:
1-2. Gitleaks secret scan (full history)
3-4. ESLint and Prettier 5. Hadolint Dockerfile lint 6. Jest unit tests with coverage
7-8. SonarCloud analysis and Snyk dependency scan
9-10. Docker image build and Trivy image vulnerability scan
11-12. ECR push via OIDC and ASG instance refresh (CD pipeline)

## Run Locally

Use Node.js 22 or newer.

From the repository root, install dependencies, run checks and tests, then start the stack:

```powershell
cd backend
npm ci
npm run lint
npm run format:check
npm test
cd ..
docker compose up --build -d
```

Or run the full local build-test script:

```powershell
./build-test.sh
```

Open <http://localhost:8080> for the frontend. The backend health endpoint is <http://localhost:3000/health>. Stop the local stack with:

```powershell
docker compose down
```

## Deploy from Scratch

### Prerequisites

- AWS account with permissions to create VPC, EC2, ALB, ASG, ECR, IAM, CloudWatch, SNS resources
- AWS CLI v2 installed and configured
- GitHub repository with OIDC provider configured for AWS
- Docker and Docker Compose installed locally

### Step 1: Provision AWS Infrastructure

Create the networking layer:

1. Create a VPC (`taskflow-vpc`) with CIDR `10.0.0.0/16` in region `ap-southeast-2`.
2. Create an Internet Gateway and attach it to the VPC.
3. Create two public subnets across two Availability Zones (`ap-southeast-2a`, `ap-southeast-2b`) and two private subnets across the same AZs.
4. Create public route tables with a route to the Internet Gateway; associate public subnets.
5. Create a NAT Gateway in a public subnet with an Elastic IP.
6. Create private route tables with a route to the NAT Gateway; associate private subnets.

Create security groups:

- **ALB Security Group**: Allow inbound HTTP on port 80 from `0.0.0.0/0`.
- **EC2 Security Group**: Allow inbound TCP on port 8080 only from the ALB Security Group. No inbound SSH.

Create IAM roles:

- **EC2 IAM Role** (`TaskFlow-EC2-SSM-Role`): Attach `AmazonSSMManagedInstanceCore`, `AmazonEC2ContainerRegistryReadOnly`, and CloudWatch agent policies. No EC2 key pair; access via SSM Session Manager only.
- **GitHub Actions OIDC Role** (`github-actions-deploy`): Trust relationship with GitHub Actions OIDC provider; permissions to push to ECR, create Launch Template versions, and start ASG instance refreshes.

Create the load balancer:

1. Create an internet-facing Application Load Balancer (`taskflow-alb`) in the public subnets across both AZs.
2. Create a target group (`taskflow-tg`) on port 8080 with health check path `/`, interval 30 seconds, healthy threshold 2, unhealthy threshold 3.
3. Register the ALB security group and add an HTTP listener on port 80 forwarding to the target group.

Create compute:

1. Create a Launch Template (`taskflow-launch-template`) using Amazon Linux 2023, instance type `t3.small`, 16 GiB gp3 root volume, IAM role `TaskFlow-EC2-SSM-Role`, and the user data script from `infra/ec2-user-data.sh`.
2. Create an Auto Scaling Group (`url-shortener-asg`) in the private subnets across both AZs, attached to the target group, with min capacity 2, desired capacity 2, max capacity 4, and a CPU target-tracking policy at 50% average CPU utilization with 300-second instance warmup.

### Step 2: Configure GitHub Secrets and Variables

Add the following to your GitHub repository Settings > Secrets and variables > Actions:

Repository secrets:

- `SONAR_TOKEN`
- `SNYK_TOKEN`
- `GITLEAKS_LICENSE` (if organization-owned)

Repository variables:

- `SONAR_ORGANIZATION`
- `SONAR_PROJECT_KEY`

Enable branch protection on `main` requiring pull requests, at least one approving review, and passing status checks.

### Step 3: Deploy the Application

1. Push code to the `main` branch. This triggers the CD pipeline (`.github/workflows/cd.yml`).
2. The pipeline:
   - Authenticates to AWS via OIDC (no hardcoded credentials).
   - Builds and pushes backend and frontend Docker images to Amazon ECR with an immutable tag (`sha-<short-sha>-<run-id>-<attempt>`).
   - Creates a new Launch Template version with the image tag injected into the user data script.
   - Sets ASG desired capacity to 2 and starts an ASG instance refresh with `MinHealthyPercentage: 50` and `SkipMatching: true`.
   - Runs a smoke test against the ALB health endpoint after refresh completes.
3. Verify the deployment:
   - All ASG instances are Healthy and InService.
   - ALB target group shows all targets healthy.
   - The application loads at the ALB DNS name (e.g., `http://taskflow-alb-1472473679.ap-southeast-2.elb.amazonaws.com`).
   - Backend `/health` returns 200.
   - Creating a short URL redirects correctly.

### Step 4: Monitoring

CloudWatch alarms and a monitoring dashboard track request rate, errors, latency, CPU, and memory. The `TaskFlow-UnhealthyTargets` alarm fires when ALB targets become unhealthy and sends an SNS email alert.

## Tear Everything Down

To remove all AWS resources created by this project:

1. **Scale down the Auto Scaling Group**:

   ```bash
   aws autoscaling update-auto-scaling-group \
     --auto-scaling-group-name url-shortener-asg \
     --min-size 0 --desired-capacity 0 --max-size 0 \
     --region ap-southeast-2
   ```

2. **Wait for instances to terminate**, then delete the Auto Scaling Group:

   ```bash
   aws autoscaling delete-auto-scaling-group \
     --auto-scaling-group-name url-shortener-asg \
     --region ap-southeast-2
   ```

3. **Delete the Launch Template**:

   ```bash
   aws ec2 delete-launch-template \
     --launch-template-id lt-014537a1cb74e6918 \
     --region ap-southeast-2
   ```

4. **Delete the Application Load Balancer and target group**:

   ```bash
   aws elbv2 delete-load-balancer \
     --load-balancer-arn arn:aws:elasticloadbalancing:ap-southeast-2:078852546033:loadbalancer/taskflow-alb \
     --region ap-southeast-2
   aws elbv2 delete-target-group \
     --target-group-arn arn:aws:elasticloadbalancing:ap-southeast-2:078852546033:targetgroup/taskflow-tg/dad74663ee8e2b40 \
     --region ap-southeast-2
   ```

5. **Delete ECR images** from `url-shortener-backend` and `url-shortener-frontend` repositories (or delete the repositories).

6. **Delete CloudWatch alarms, dashboard, and log groups** (`/aws/ec2/url-shortener`).

7. **Delete networking**:
   - Delete private subnets, then public subnets.
   - Delete route tables (after disassociating subnets).
   - Delete the NAT Gateway and release its Elastic IP.
   - Detach and delete the Internet Gateway.
   - Delete security groups.
   - Delete the VPC.

8. **Delete IAM roles** (`TaskFlow-EC2-SSM-Role` and `github-actions-deploy`) after removing attached policies.

9. **Remove GitHub repository secrets, variables, and branch protection rules** if no longer needed.
