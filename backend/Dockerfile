# Dockerfile für Google Cloud Run
FROM python:3.11-slim

# System Dependencies
RUN apt-get update && apt-get install -y \
    ffmpeg \
    git \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Python Dependencies (minimal für schnellen Build)
COPY requirements-render.txt requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# LivePortrait installieren
RUN git clone https://github.com/KwaiVGI/LivePortrait.git /opt/liveportrait

WORKDIR /opt/liveportrait

# PyTorch CPU-only
RUN pip install --no-cache-dir torch torchvision --index-url https://download.pytorch.org/whl/cpu

# LivePortrait Dependencies
RUN pip install --no-cache-dir opencv-python-headless numpy pillow tyro pyyaml tqdm imageio scikit-image

# Backend Code - zurück zum Root-App-Verzeichnis (absoluter Pfad!)
WORKDIR /app

# Kopiere Backend Files explizit
COPY main.py /app/
COPY generate_dynamics_endpoint.py /app/

# Environment
ENV PYTHONUNBUFFERED=1
ENV PYTHONPATH=/app
ENV LIVEPORTRAIT_PATH="/opt/liveportrait/inference.py"
ENV PYTORCH_ENABLE_MPS_FALLBACK="1"
ENV PORT=8080

EXPOSE 8080

# Start (mit Python3 explizit)
CMD ["python3", "-m", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]

