terraform {
  backend "s3" {
    bucket         = "my-terraform-state-akefe-123"
    key            = "TESTINGMYARTICLE/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}