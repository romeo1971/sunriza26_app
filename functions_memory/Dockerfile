FROM node:20-slim

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm install --omit=dev

# Copy built app
COPY lib ./lib

# Run as non-root user
USER node

# Expose port
EXPOSE 8080

# Start the server
CMD ["node", "lib/index.js"]





