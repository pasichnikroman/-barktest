output "instance_public_ip" {
  value = aws_instance.bark_service.public_ip
}

output "instance_id" {
  value = aws_instance.bark_service.id
}

output "s3_bucket" {
  value = aws_s3_bucket.bark_outputs.bucket
}
