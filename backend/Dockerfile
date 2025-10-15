# Dockerfile für Google Cloud Run - Dynamics Service
FROM python:3.11-slim

# System Dependencies
RUN apt-get update && apt-get install -y \
    ffmpeg \
    git \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Python Dependencies
COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# LivePortrait installieren
RUN git clone https://github.com/KwaiVGI/LivePortrait.git /opt/liveportrait

WORKDIR /opt/liveportrait

# PyTorch CPU-only
RUN pip install --no-cache-dir torch torchvision --index-url https://download.pytorch.org/whl/cpu

# LivePortrait Dependencies
RUN pip install --no-cache-dir opencv-python-headless numpy pillow tyro pyyaml tqdm imageio scikit-image

# Zurück zum App-Verzeichnis
WORKDIR /app

# Backend Code kopieren
COPY main.py /app/
COPY generate_dynamics_endpoint.py /app/

# Environment Variables
ENV PYTHONUNBUFFERED=1
ENV PYTHONPATH=/app
ENV LIVEPORTRAIT_PATH="/opt/liveportrait/inference.py"
ENV PYTORCH_ENABLE_MPS_FALLBACK="1"

EXPOSE 8080

# Start - Cloud Run setzt PORT automatisch
CMD ["sh", "-c", "python3 -m uvicorn main:app --host 0.0.0.0 --port ${PORT:-8080}"]
