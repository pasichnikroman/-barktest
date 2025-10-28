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
  region = var.aws_region
}

resource "aws_s3_bucket" "bark_outputs" {
  bucket = var.s3_bucket_name
  acl    = "public-read"
  force_destroy = true

  versioning {
    enabled = false
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
}

resource "aws_security_group" "bark_sg" {
  name        = "bark-service-sg"
  description = "Allow SSH and HTTP (5000)"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 5000
    to_port     = 5000
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

# Use an Amazon Linux 2 with CUDA / GPU support (choose appropriate AMI in your region if needed)
variable "ami_id" {
  type = string
  description = "AMI id to use for the EC2 instance (GPU-enabled AMI recommended)"
  default = ""
}

resource "aws_instance" "bark_service" {
  ami           = length(var.ami_id) > 0 ? var.ami_id : data.aws_ami.default.id
  instance_type = var.instance_type
  key_name      = var.key_name
  vpc_security_group_ids = [aws_security_group.bark_sg.id]

  root_block_device {
    volume_size           = 100
    volume_type           = "gp3"
    delete_on_termination = true
  }

  user_data = <<-EOF
  #!/bin/bash
  set -ex

  # Run as ec2-user (Amazon Linux)
  cd /home/ec2-user

  # Install updates and prerequisites
  sudo yum update -y
  sudo yum install -y docker git unzip amazon-linux-extras python3

  # Enable docker
  sudo systemctl enable docker
  sudo systemctl start docker
  sudo usermod -a -G docker ec2-user

  # Install NVIDIA drivers and nvidia-docker2
  # (This uses the NVIDIA repo; on some AMIs drivers may be preinstalled.)
  distribution=$(. /etc/os-release; echo $ID$VERSION_ID)
  curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo rpm --import -
  curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.repo | sudo tee /etc/yum.repos.d/nvidia-docker.repo
  sudo yum clean expire-cache
  sudo yum install -y nvidia-docker2
  sudo systemctl restart docker || true

  # Create app dir and switch ownership
  sudo mkdir -p /home/ec2-user/bark
  sudo chown ec2-user:ec2-user /home/ec2-user/bark
  cd /home/ec2-user/bark

  # Place minimal files (we'll pull the full app from S3 or you can SCP them)
  # For convenience, we will download the Dockerfile and app from a temporary bundle if provided
  # But in this package we assume user will upload files to the instance or to an accessible git repo.

  # If git repo is provided, clone it (replace <your-git> if you use GitHub)
  # git clone https://github.com/<your-repo>/bark-service.git . || true

  # Build Docker image from local files (if present)
  if [ -f Dockerfile ]; then
    sudo docker build -t bark-service . || true
  fi

  # Run the container (bind to 0.0.0.0:5000) with GPU support
  sudo docker run -d --restart always --gpus all -p 5000:5000 -e S3_BUCKET={"${var.s3_bucket_name}"} -e AWS_REGION={"${var.aws_region}"} --name bark-service bark-service || true
  EOF

  tags = {
    Name = "Bark-GPU-Service"
  }
}

data "aws_ami" "default" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-gp2"]
  }
}
