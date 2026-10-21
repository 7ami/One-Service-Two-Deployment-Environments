
FROM node:22-alpine


WORKDIR /app


COPY package.json ./
COPY src ./src


ENV PORT=8080 \
    SERVICE_NAME=cs554-midterm \
    MESSAGE="Hello from the CS 554 deployment project!"


USER node


EXPOSE 8080


CMD ["node", "src/server.js"]

