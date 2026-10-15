# Use a specific, pinned lightweight LTS Node.js Alpine base image
FROM node:22-alpine

# Set non-root execution directory
WORKDIR /app

# Copy application definition and source code
COPY package.json ./
COPY src ./src

# Set environment defaults (overridable at runtime)
ENV PORT=8080 \
    SERVICE_NAME=cs554-midterm \
    MESSAGE="Hello from the CS 554 deployment project!"

# Run as non-root user for security best practices
USER node

# Document the default application listening port
EXPOSE 8080

# Execute the service process directly without shell wrapping
CMD ["node", "src/server.js"]
