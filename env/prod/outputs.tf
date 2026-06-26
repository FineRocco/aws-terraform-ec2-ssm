
output "ecr_repository_url" {
  description = "The ECR URL for the GitHub Actions pipeline"
  value       = module.dev_stack.ecr_repository_url
}

output "dev_db_endpoint" {
  description = "The RDS connection string"
  value       = module.dev_stack.db_endpoint
}

output "dev_web_public_ip" {
  description = "The public IP of the Dev web server"
  value       = module.dev_stack.web_public_ip
}