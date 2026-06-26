
provider "aws" {
  region = "eu-west-1"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["1b511abead59c6ce207077c0bf0e0043b1382612", "6938fd4d98bab03faadb97b34396831e3780aea1"] 
}

resource "aws_iam_role" "github_actions_role" {
  name = "GitHubActionsRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            # STRICT SECURITY: Only allow YOUR specific repo to assume this role!
            "token.actions.githubusercontent.com:sub" = "repo:FineRocco/aws-terraform:*"
          }
        }
      }
    ]
  })
}

# 3. Attach Administrator permissions so GitHub Actions can build your infrastructure
# Note: In a true enterprise prod environment, we would scope this down further, 
# but Admin is standard for a CI/CD role deploying core networking/compute.
resource "aws_iam_role_policy_attachment" "github_actions_admin" {
  role       = aws_iam_role.github_actions_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# 4. Output the exact ARN so you can copy-paste it into your GitHub YAML
output "github_actions_role_arn" {
  value       = aws_iam_role.github_actions_role.arn
  description = "Copy this ARN into your pr-plan.yml file"
}