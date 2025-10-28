variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "key_name" {
  description = "EC2 key pair name"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type (GPU)"
  type        = string
  default     = "g4dn.xlarge"
}

variable "s3_bucket_name" {
  description = "S3 bucket name to store generated wav files (must be globally unique)"
  type        = string
}
