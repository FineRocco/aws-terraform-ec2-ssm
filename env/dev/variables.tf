variable "environment" {
  description = "The deployment environment (dev, prod)"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance size"
  type        = string
}

variable "db_password" {
  description = "The password for the RDS PostgreSQL database"
  type        = string
  sensitive   = true
}