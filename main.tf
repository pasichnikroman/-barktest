terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.4.0"
}

provider "aws" {
  region = "us-east-1"
}

# Variables
variable "key_name" {
  description = "Your AWS key pair name"
  type        = string
}

variable "instance_type" {
  default = "t3.medium"
}

variable "ami" {
  # Amazon Linux 2023 AMI in us-east-1
  default = "ami-0c101f26f147fa7fd"
}

variable "security_group_name" {
  default = "bark-sg"
}

# Security Group
resource "aws_security_group" "bark_sg" {
  name        = var.security_group_name
  description = "Allow SSH"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# EC2 Instance
resource "aws_instance" "bark_ec2" {
  ami           = var.ami
  instance_type = var.instance_type
  key_name      = var.key_name
  security_groups = [aws_security_group.bark_sg.name]

  # Increase root volume size to 30 GB
  root_block_device {
    volume_size           = 30
    volume_type           = "gp3"
    delete_on_termination = true
  }

  user_data = <<-EOF
  #!/bin/bash
  set -ex

  # Update system
  sudo yum update -y

  # Install Docker
  sudo yum install -y docker

  # Enable and start Docker service
  sudo systemctl enable docker
  sudo systemctl start docker

  # Allow ec2-user to use Docker without sudo
  sudo usermod -aG docker ec2-user

  echo "✅ Docker setup complete"
EOF

  tags = {
    Name = "Bark-EC2"
  }
}

# Outputs
output "public_ip" {
  value = aws_instance.bark_ec2.public_ip
}

output "instance_id" {
  value = aws_instance.bark_ec2.id
}
