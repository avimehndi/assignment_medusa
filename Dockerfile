# Use Node.js 18 Alpine as base image for smaller size
FROM node:18-alpine

# Install system dependencies
RUN apk add --no-cache \
    python3 \
    make \
    g++ \
    curl \
    git

# Create app directory
WORKDIR /app

# Copy package files
COPY package*.json ./
COPY yarn.lock ./

# Install dependencies
RUN yarn install --frozen-lockfile --production=false

# Copy source code
COPY . .

# Build the application
RUN yarn build

# Change to the build directory
WORKDIR /app/.medusa/server

# Install production dependencies in build directory
RUN yarn install --frozen-lockfile --production=true

# Expose port
EXPOSE 9000

# Add health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=3 \
    CMD curl -f http://localhost:9000/health || exit 1

# Create startup script
RUN echo '#!/bin/sh\n\
echo "Starting Medusa application..."\n\
echo "Running database migrations..."\n\
yarn medusa db:migrate\n\
echo "Syncing links..."\n\
yarn medusa links:sync\n\
echo "Starting server..."\n\
yarn start' > /app/start.sh && chmod +x /app/start.sh

# Start the application
CMD ["/app/start.sh"]
