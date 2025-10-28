import os
import uuid
import time
from flask import Flask, request, jsonify, send_file
import torch
from bark import SAMPLE_RATE, generate_audio
from scipy.io.wavfile import write as write_wav
import boto3

# Load env vars
S3_BUCKET = os.environ.get("S3_BUCKET")
AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")

app = Flask(__name__)

# Optional compatibility patch for some torch/bark combos
try:
    old_load = torch.load
    def patched_load(*args, **kwargs):
        kwargs.setdefault('weights_only', False)
        return old_load(*args, **kwargs)
    torch.load = patched_load
except Exception:
    pass

@app.route("/generate", methods=["POST"])
def generate():
    data = request.get_json(force=True)
    text = data.get("text")
    if not text:
        return jsonify({"error": "Missing 'text'"}), 400

    # Make outputs dir
    out_dir = "/app/outputs"
    os.makedirs(out_dir, exist_ok=True)

    filename = f"output_{int(time.time())}_{uuid.uuid4().hex[:8]}.wav"
    filepath = os.path.join(out_dir, filename)

    # Choose device (BARK internally uses torch)
    device = "cuda" if torch.cuda.is_available() else "cpu"
    app.logger.info(f"Using device: {device}")

    # Generate audio (may stream model weights the first run)
    audio_array = generate_audio(text)

    # Save as WAV
    write_wav(filepath, SAMPLE_RATE, audio_array)
    app.logger.info(f"Saved file to {filepath}")

    # If S3 configured, upload and return public url
    if S3_BUCKET:
        s3 = boto3.client('s3', region_name=AWS_REGION)
        key = f"bark-outputs/{filename}"
        s3.upload_file(filepath, S3_BUCKET, key, ExtraArgs={'ACL': 'public-read', 'ContentType': 'audio/wav'})
        # Construct public URL (works for public bucket or public-read objects)
        url = f"https://{S3_BUCKET}.s3.amazonaws.com/{key}"
        return jsonify({"message": "✅ Song generated", "s3_url": url, "local_path": filepath})
    else:
        return jsonify({"message": "✅ Song generated", "local_path": filepath})

@app.route("/download/<filename>", methods=["GET"])
def download(filename):
    path = os.path.join("/app/outputs", filename)
    if not os.path.exists(path):
        return jsonify({"error": "File not found"}), 404
    return send_file(path, as_attachment=True)

if __name__ == '__main__':
    device = "cuda" if torch.cuda.is_available() else "cpu"
    print(f"Starting BARK service (device={device})")
    app.run(host="0.0.0.0", port=5000)
