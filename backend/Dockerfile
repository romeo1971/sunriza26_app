# Dockerfile für Sunriza Backend (Render.com)
FROM python:3.13-slim

# System Dependencies installieren
RUN apt-get update && apt-get install -y \
    ffmpeg \
    git \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Arbeitsverzeichnis
WORKDIR /app

# Python Dependencies installieren (Render.com CPU-only)
COPY requirements-render.txt requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# LivePortrait installieren
RUN git clone https://github.com/KwaiVGI/LivePortrait.git /opt/liveportrait
WORKDIR /opt/liveportrait

# Installiere PyTorch CPU-only (ohne CUDA)
RUN pip install --no-cache-dir torch torchvision --index-url https://download.pytorch.org/whl/cpu

# Installiere andere LivePortrait Dependencies
RUN pip install --no-cache-dir opencv-python numpy pillow tyro pyyaml tqdm imageio

# Pretrained Weights herunterladen
# Note: Diese müssen separat heruntergeladen werden, siehe README
# https://github.com/KwaiVGI/LivePortrait#-download-pretrained-weights

# Backend Code kopieren
WORKDIR /app
COPY . .

# Umgebungsvariablen
ENV LIVEPORTRAIT_PATH="/opt/liveportrait/inference.py"
ENV PYTORCH_ENABLE_MPS_FALLBACK="1"
ENV PORT=8002

# Port freigeben
EXPOSE 8002

# Health Check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python -c "import requests; requests.get('http://localhost:8002/health')"

# Backend starten
CMD uvicorn main:app --host 0.0.0.0 --port $PORT

