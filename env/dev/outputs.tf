output "ecr_repository_url" {
  description = "The ECR URL for the GitHub Actions pipeline"
  value       = module.prod_stack.ecr_repository_url
}

output "prod_db_endpoint" {
  description = "The RDS connection string for Prod"
  value       = module.prod_stack.db_endpoint
}

output "prod_web_public_ip" {
  description = "The public IP of the Prod web server"
  value       = module.prod_stack.web_public_ip
}