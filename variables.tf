variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for private subnet"
  type        = string
  default     = "10.0.2.0/24"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "my-vpc"
}

variable "private_subnet_2_cidr" {
  description = "CIDR block for the second private subnet"
  type        = string
  default     = "10.0.3.0/24"
}

# Database Credentials
variable "db_username" {
  description = "Database master username"
  type        = string
  default     = "flask_user"
}

variable "db_password" {
  description = "Database master password"
  type        = string
  sensitive   = true
  default     = "admin1234"
}