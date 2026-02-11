packer {
  required_plugins {
    amazon = {
      version = ">= 1.2.8"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

variable "region" {
  type    = string
  default = "us-east-1"
}

source "amazon-ebs" "flask-app" {
  ami_name      = "flask-app-ami-{{timestamp}}"
  instance_type = "t2.micro"
  region        = var.region
  
  # Base Image: Amazon Linux 2023 (or 2 depending on your preference)
  source_ami_filter {
    filters = {
      name                = "al2023-ami-2023.*-x86_64"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["amazon"]
  }
  
  ssh_username = "ec2-user"
}

build {
  name    = "flask-builder"
  sources = ["source.amazon-ebs.flask-app"]

  # 1. Upload Application Files to Temporary Location
  provisioner "file" {
    source      = "./files/"
    destination = "/home/ec2-user/"
  }

  # 2. Setup Script (Install dependencies & Move files)
  provisioner "shell" {
    inline = [
      "echo '--- Installing System Dependencies ---'",
      "sudo yum update -y",
      "sudo yum install -y python3-pip nginx git",

      "echo '--- Installing Python Dependencies ---'",
      "pip3 install -r /home/ec2-user/requirements.txt",

      "echo '--- Configuring Nginx ---'",
      # We overwrite the default server block with our proxy pass config
      "sudo tee /etc/nginx/conf.d/flask.conf > /dev/null <<EOT",
      "server {",
      "    listen 80;",
      "    location / {",
      "        proxy_pass http://127.0.0.1:8000;",
      "        proxy_set_header Host \\$host;",
      "        proxy_set_header X-Real-IP \\$remote_addr;",
      "    }",
      "}",
      "EOT",
      
      # Remove default welcome page config if it exists
      "sudo rm -f /etc/nginx/conf.d/default.conf", 
      
      "echo '--- Configuring Systemd Service ---'",
      "sudo mv /home/ec2-user/myflaskapp.service /etc/systemd/system/myflaskapp.service",
      "sudo systemctl daemon-reload",
      "sudo systemctl enable myflaskapp",
      "sudo systemctl enable nginx",
      
      "echo '--- Creating Templates Directory ---'",
      # (Note: You should also add index.html to your files folder and upload it if you want it pre-baked)
    ]
  }
}