FROM ubuntu:22.04

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    git \
    unzip \
    xz-utils \
    zip \
    libglu1-mesa \
    && rm -rf /var/lib/apt/lists/*

# Install Flutter
RUN git clone https://github.com/flutter/flutter.git /flutter
ENV PATH="/flutter/bin:${PATH}"

# Enable Flutter web
RUN flutter config --enable-web

# Set working directory
WORKDIR /app

# Copy Flutter app
COPY . .

# Get Flutter dependencies
RUN flutter pub get

# Build Flutter web app
RUN flutter build web --release

# Install Python for backend
RUN apt-get update && apt-get install -y python3 python3-pip && rm -rf /var/lib/apt/lists/*

# Copy and install Python requirements
COPY backend/requirements.txt /app/backend/
RUN pip3 install -r /app/backend/requirements.txt

# Copy backend
COPY backend/ /app/backend/

# Expose port
EXPOSE 4202

# Start both Flutter web server and Python backend
CMD ["sh", "-c", "cd /app && python3 -m http.server 4202 --directory build/web & cd /app/backend && python3 avatar_backend.py"]
