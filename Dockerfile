# GPU-enabled image with PyTorch + CUDA runtime
FROM pytorch/pytorch:2.3.0-cuda12.1-cudnn8-runtime


WORKDIR /app

# System deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    libsndfile1 ffmpeg git && rm -rf /var/lib/apt/lists/*

# Python deps
COPY requirements.txt /app/requirements.txt
RUN pip install --upgrade pip
RUN pip install --no-cache-dir -r /app/requirements.txt

# Copy app
COPY bark_app.py /app/bark_app.py

# Create output dir
RUN mkdir -p /app/outputs

EXPOSE 5000

CMD ["python", "bark_app.py"]
