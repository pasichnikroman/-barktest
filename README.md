# Bark-Service (AWS GPU + S3)

This package contains a minimal GPU-backed Flask service that generates audio using Suno's Bark model,
packages it in a Docker container, and uploads generated WAV files to Amazon S3.

----
## Files included
- `bark_app.py`         : Flask application that exposes POST /generate
- `Dockerfile`         : Dockerfile (based on PyTorch CUDA image)
- `requirements.txt`   : Python dependencies
- `.env.example`       : Example environment variables
- `terraform/`         : Terraform config to create EC2 + S3

----
## Quick deploy (manual)

1. Build Docker image locally (if testing locally with GPU):
   ```bash
   docker build -t bark-service .
   docker run --gpus all -p 5000:5000 -e S3_BUCKET=your-bucket -e AWS_REGION=us-east-1 bark-service
   ```

2. Call the service:
   ```bash
   curl -X POST http://localhost:5000/generate -H "Content-Type: application/json" -d '{"text":"Hello from the cloud"}'
   ```

----
## Terraform deploy (automatic)
1. Edit `terraform/variables.tf` defaults OR provide variables on the CLI:
   - `key_name` : your EC2 key pair (e.g. MyKeyPair)
   - `s3_bucket_name` : globally unique bucket name (e.g. roman-bark-outputs-2025-10-27)
   - `aws_region` : us-east-1

2. Initialize & apply:
   ```bash
   cd terraform
   terraform init
   terraform apply -var='key_name=MyKeyPair' -var='s3_bucket_name=your-unique-bucket' -var='aws_region=us-east-1'
   ```

3. After apply, get the public IP from Terraform outputs and copy the files to the EC2 instance (if Dockerfile and app didn't build there automatically):
   ```bash
   # Example to copy files (from repo root)
   scp -i /path/to/MyKeyPair.pem Dockerfile bark_app.py requirements.txt ec2-user@<EC2_PUBLIC_IP>:/home/ec2-user/bark/
   ssh -i /path/to/MyKeyPair.pem ec2-user@<EC2_PUBLIC_IP>
   cd /home/ec2-user/bark
   sudo docker build -t bark-service .
   sudo docker run -d --restart always --gpus all -p 5000:5000 -e S3_BUCKET=your-unique-bucket -e AWS_REGION=us-east-1 bark-service
   ```

----
## Notes & troubleshooting
- The user-data attempts to install `nvidia-docker2` on Amazon Linux. Depending on the AMI you choose, drivers may already be present.
- If the user-data build fails, you can SSH in and build/run the Docker container manually (see commands above).
- Ensure the EC2 instance type supports NVIDIA GPUs (e.g. `g4dn.xlarge`) and that the AMI supports the drivers for that GPU.

----
## Security
- The S3 bucket is created with `public-read` ACL in this example for convenience. For production, use pre-signed URLs or private buckets.
- The service listens on port 5000; consider using a proxy (nginx) and HTTPS for production.
