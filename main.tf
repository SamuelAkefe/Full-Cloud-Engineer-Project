terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }

    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Data Source for Availability aws_availability_zones
data "aws_availability_zones" "available" {
  state = "available"
}

# Create a VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# Create a public subnet 
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-subnet"
  }
}

# Create a private subnet 
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "${var.project_name}-private-subnet"
  }
}

# Create another Private Subnet.
resource "aws_subnet" "private_subnet_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_2_cidr
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "${var.project_name}-private-subnet-2"
  }
}

resource "aws_db_subnet_group" "rds_group" {
  name = "${var.project_name}-rds-group"
  subnet_ids = [
    aws_subnet.private.id,
    aws_subnet.private_subnet_2.id
  ]

  tags = {
    Name = "${var.project_name}-rds-group"
  }
}

#3. Create RDS SECURITY GROUP
resource "aws_security_group" "rds_sg" {
  name        = "${var.project_name}-rds-sg"
  description = "Allow inbound traffic from Web App"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Postgres from Web Server"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    # Allow traffic ONLY from your Web Server's Security group
    security_groups = [aws_security_group.public_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-rds-dg"
  }
}

#4. Create the RDS instance_type
resource "aws_db_instance" "postgres" {
  identifier        = "${var.project_name}-db"
  allocated_storage = 20
  storage_type      = "gp2"
  engine            = "postgres"
  engine_version    = "14"
  instance_class    = "db.t3.micro"
  db_name           = "flask_db"
  username          = var.db_username
  password          = var.db_password

  # SECURITY FIX
  storage_encrypted = true

  # Network & Security
  db_subnet_group_name   = aws_db_subnet_group.rds_group.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  publicly_accessible    = false
  skip_final_snapshot    = true # Good for dev/learning, dangerous for prod!

  tags = {
    Name = "${var.project_name}-db"
  }
}


# Create Internet Gateway 
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# Create Elastic IP for NAT Gateway
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-nat-eip"
  }

  depends_on = [aws_internet_gateway.main]
}

# Create NAT Gateway
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id

  tags = {
    Name = "${var.project_name}-nat-gateway"
  }

  depends_on = [aws_internet_gateway.main]
}

# Create Public Route Table 
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

# Create Private Route Table 
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-private-rt"
  }
}

# Associate Public Subnet with Route Table 
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Associate Private Subnet with Route Table
resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# Associate Private Subnet2 with Route Table
resource "aws_route_table_association" "private_2" {
  subnet_id      = aws_subnet.private_subnet_2.id
  route_table_id = aws_route_table.private.id
}

#--------MYEC2INSTANCE--------------
# Generate a secure private key in memory
resource "tls_private_key" "os_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Upload the Public key to AWS
resource "aws_key_pair" "generated_key" {
  key_name   = "${var.project_name}-key"
  public_key = tls_private_key.os_key.public_key_openssh
}

# Save the Private Key to a local file (pem key)
resource "local_file" "private_key_pem" {
  content  = tls_private_key.os_key.private_key_pem
  filename = "${path.module}/my-key.pem"
}


resource "aws_security_group" "public_sg" {
  name        = "${var.project_name}-public-sg"
  description = "Allow SSH inbound traffic"
  vpc_id      = aws_vpc.main.id

  # Inbound Rule: Allow SSH (Port 22)
  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # For the tutorial, we allow all. In prod, restrict this!
  }

  # Inbound Rule: Allow HTTP (Port 80) for Nginx
  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound Rule: Allow all traffic (crucial for updates!)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-public-sg"
  }
}

# Get the latest Amazon Linux 2 AMI automatically
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_instance" "public_server" {
  ami           = "ami-075943ca530190a76"
  instance_type = "t2.micro"

  # Place it in the Public Subnet (from the previous article context)
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.public_sg.id]
  associate_public_ip_address = true

  # Encrypt the hard drive (AVD-AWS-0131)
  root_block_device {
    encrypted = true
  }

  # Force IMDSv2 (Token required) (AVD-AWS-0028)
  # This prevents SSRF attacks
  metadata_options {
    http_tokens = "required"
  }

  # Attach the key pair we created in Step 1
  key_name = aws_key_pair.generated_key.key_name

  # IAM_instance_profile 
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name

  # Instead of installing software (which is already done), this script connects the app to RDS and S3.
  user_data = <<-EOF
#!/bin/bash

# Create a systemd override Directory
mkdir -p /etc/systemd/system/myflaskapp.service.d

# Write the Database & S3 details into a config file
cat <<EOT > /etc/systemd/system/myflaskapp.service.d/override.conf
    [Service]
    Environment="RDS_ENDPOINT=${aws_db_instance.postgres.endpoint}"
    Environment="DB_USER=${var.db_username}"
    Environment="DB_PASSWORD=${var.db_password}"
    Environment="S3_BUCKET_NAME=${aws_s3_bucket.uploads.bucket}"
EOT
# Reload systemd to read the new config
systemctl daemon-reload

# Restart the app so it connects to the database
systemctl restart myflaskapp
EOF

  tags = {
    Name = "${var.project_name}-ec2"
  }

  # Prevent Terraform from destroying the instance if the script changes slightly
  lifecycle {
    ignore_changes = [user_data, tags]
  }
}

# Allow DMS TO ACCESS EC2 (Source)
resource "aws_security_group_rule" "allow_dms_to_ec2" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.dms_sg.id # Allow DMS sg

  security_group_id = aws_security_group.public_sg.id # Add rule to EC2 SG 
}

# ALLOW DMS TO ACCESS RDS (Target)
resource "aws_security_group_rule" "allow_dms_to_rds" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.dms_sg.id # Allow DMS SG

  security_group_id = aws_security_group.rds_sg.id # Add rule to RDS SG
}