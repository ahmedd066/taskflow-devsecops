# ECR Repository Setup

Run these commands **once** to create the ECR repositories with tag immutability enabled.

## Prerequisites
- AWS CLI v2 configured with credentials for account `078852546033`
- Region: `ap-southeast-2`

## Commands

```bash
# Backend repository
aws ecr create-repository \
  --repository-name url-shortener-backend \
  --region ap-southeast-2 \
  --image-tag-mutability IMMUTABLE \
  --image-scanning-configuration scanOnPush=true

# Frontend repository
aws ecr create-repository \
  --repository-name url-shortener-frontend \
  --region ap-southeast-2 \
  --image-tag-mutability IMMUTABLE \
  --image-scanning-configuration scanOnPush=true
```

## Expected Output

Each command returns a JSON response. Note the `repositoryUri` values:

```json
{
  "repository": {
    "repositoryUri": "078852546033.dkr.ecr.ap-southeast-2.amazonaws.com/url-shortener-backend",
    ...
  }
}
```

## Values to Share with Member 3

| Variable | Value (replace with your output) |
|----------|----------------------------------|
| `ECR_BACKEND_REPO` | `078852546033.dkr.ecr.ap-southeast-2.amazonaws.com/url-shortener-backend` |
| `ECR_FRONTEND_REPO` | `078852546033.dkr.ecr.ap-southeast-2.amazonaws.com/url-shortener-frontend` |

## Verify Repositories Exist

```bash
aws ecr describe-repositories \
  --repository-names url-shortener-backend url-shortener-frontend \
  --region ap-southeast-2 \
  --query 'repositories[*].[repositoryName,repositoryUri]' \
  --output table
```

## Tag Immutability

`--image-tag-mutability IMMUTABLE` prevents overwriting existing tags (required by project spec). The CD pipeline will push unique tags per commit (SHA + semantic version).

## Image Scanning

`--image-scanning-configuration scanOnPush=true` enables automatic vulnerability scanning on push (complements Trivy in CI).