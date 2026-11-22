# IAM Permissions for GitHub Actions Deployment Role

Attach this policy to the `github-actions-deploy` IAM role (OIDC trust with GitHub).

## Role Trust Policy (OIDC)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::078852546033:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:ahmedd066/taskflow-devsecops:*"
        }
      }
    }
  ]
}
```

> **Note:** Replace `ahmedd066/taskflow-devsecops` with your actual GitHub org/repo.

---

## Inline Policy: `TaskFlow-GitHubActions-Deploy`

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ECRReadWrite",
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchGetImage",
        "ecr:GetDownloadUrlForLayer",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:DescribeRepositories",
        "ecr:DescribeImages"
      ],
      "Resource": [
        "arn:aws:ecr:ap-southeast-2:078852546033:repository/url-shortener-backend",
        "arn:aws:ecr:ap-southeast-2:078852546033:repository/url-shortener-frontend"
      ]
    },
    {
      "Sid": "ASGInstanceRefresh",
      "Effect": "Allow",
      "Action": [
        "autoscaling:StartInstanceRefresh",
        "autoscaling:DescribeInstanceRefreshes",
        "autoscaling:CancelInstanceRefresh",
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeLaunchTemplates",
        "autoscaling:CreateOrUpdateTags"
      ],
      "Resource": [
        "arn:aws:autoscaling:ap-southeast-2:078852546033:autoScalingGroup:*:autoScalingGroupName/*"
      ]
    },
    {
      "Sid": "LaunchTemplateUpdate",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateLaunchTemplateVersion",
        "ec2:DescribeLaunchTemplates",
        "ec2:DescribeLaunchTemplateVersions",
        "ec2:ModifyLaunchTemplate"
      ],
      "Resource": [
        "arn:aws:ec2:ap-southeast-2:078852546033:launch-template/lt-014537a1cb74e6918"
      ]
    },
    {
      "Sid": "SSMParameterRead",
      "Effect": "Allow",
      "Action": [
        "ssm:GetParameter",
        "ssm:GetParameters",
        "ssm:GetParametersByPath"
      ],
      "Resource": [
        "arn:aws:ssm:ap-southeast-2:078852546033:parameter/url-shortener/*"
      ]
    },
    {
      "Sid": "CloudWatchLogsRead",
      "Effect": "Allow",
      "Action": [
        "logs:GetLogEvents",
        "logs:FilterLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ],
      "Resource": [
        "arn:aws:logs:ap-southeast-2:078852546033:log-group:/aws/ec2/url-shortener:*"
      ]
    }
  ]
}
```

---

## Minimum Permissions Summary

| Service | Actions | Resources |
|---------|---------|-----------|
| **ECR** | Push/pull images, get auth token | Both repos |
| **ASG** | Start/describe/cancel instance refresh | Specific ASG (by name pattern) |
| **EC2 Launch Template** | Create new version, describe | `lt-014537a1cb74e6918` |
| **SSM Parameter Store** | Read parameters under `/url-shortener/*` | Parameter path |
| **CloudWatch Logs** | Read logs for debugging | Log group `/aws/ec2/url-shortener` |

---

## How to Create (Member 3)

```bash
# 1. Create OIDC provider (if not exists)
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1

# 2. Create role with trust policy
aws iam create-role \
  --role-name github-actions-deploy \
  --assume-role-policy-document file://trust-policy.json

# 3. Attach inline policy
aws iam put-role-policy \
  --role-name github-actions-deploy \
  --policy-name TaskFlow-GitHubActions-Deploy \
  --policy-document file://deploy-policy.json
```

## Output to Share with Member 4

After creation, run:
```bash
aws iam get-role --role-name github-actions-deploy --query 'Role.Arn' --output text
```

Share the ARN: `arn:aws:iam::078852546033:role/github-actions-deploy`