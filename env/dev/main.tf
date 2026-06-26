module "dev_stack" {
  source = "../../modules/web_database_stack"
  
  environment    = var.environment
  instance_type  = var.instance_type
  db_password    = var.db_password 
}