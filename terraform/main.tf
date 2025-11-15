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
  force_destroy = true

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
}
# S3 versioning (replacement for deprecated versioning block)
resource "aws_s3_bucket_versioning" "bark_outputs_versioning" {
  bucket = aws_s3_bucket.bark_outputs.id
  versioning_configuration {
    status = "Suspended"  # Change to "Enabled" if you want versioning on
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

cd /home/ec2-user

# Install base packages
sudo yum update -y
sudo yum install -y docker git unzip python3 gcc make kernel-devel-$(uname -r) kernel-headers-$(uname -r)

# Enable and start Docker
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker ec2-user

#############################################
# INSTALL NVIDIA DRIVER + NVIDIA DOCKER RUNTIME
#############################################

# Add NVIDIA docker repo (correct for Amazon Linux 2)
curl -s -L https://nvidia.github.io/nvidia-container-runtime/amzn2/nvidia-container-runtime.repo \
  | sudo tee /etc/yum.repos.d/nvidia-container-runtime.repo

# Install container runtime + driver metapackage
sudo yum install -y nvidia-container-runtime nvidia-driver-latest-dkms

# Configure Docker to use NVIDIA runtime
sudo tee /etc/docker/daemon.json > /dev/null <<EOT
{
  "default-runtime": "nvidia",
  "runtimes": {
    "nvidia": {
      "path": "/usr/bin/nvidia-container-runtime",
      "runtimeArgs": []
    }
  }
}
EOT

sudo systemctl restart docker

#############################################
# DEPLOY BARK APP
#############################################
sudo mkdir -p /home/ec2-user/bark
sudo chown ec2-user:ec2-user /home/ec2-user/bark
cd /home/ec2-user/bark

# Clone repo
git clone https://github.com/pasichnikroman/-barktest.git . || true

# Build image if Dockerfile exists
if [ -f Dockerfile ]; then
  sudo docker build -t bark-service . || true
fi

# Run Bark GPU container
sudo docker run -d --restart always --gpus all \
  -p 5000:5000 \
  -e S3_BUCKET=${var.s3_bucket_name} \
  -e AWS_REGION=${var.aws_region} \
  --name bark-service \
  bark-service || true

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
    values = ["amzn2-ami-hvm-*-x86_64-gp2"] # <-- x86_64 AMI for GPU instances
  }
}
