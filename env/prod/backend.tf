terraform {
  backend "s3" {
    bucket         = "denis-tf-state-bucket"
    key            = "prod/terraform.tfstate"
    region         = "eu-west-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}
