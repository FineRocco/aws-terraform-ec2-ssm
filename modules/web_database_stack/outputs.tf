output "web_public_ip" {
  description = "The public IP address of the EC2 web server"
  value       = aws_instance.web.public_ip
}

output "db_endpoint" {
  description = "The connection string for the RDS PostgreSQL database"
  value       = aws_db_instance.postgres.endpoint
}

output "ecr_repository_url" {
  description = "The URL of the ECR repository to push Docker images to"
  value       = aws_ecr_repository.app_repo.repository_url
}