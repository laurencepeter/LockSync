FROM node:20-alpine

WORKDIR /app

COPY package.json package-lock.json* ./
RUN npm install --omit=dev --ignore-scripts

COPY src/ src/

# Non-root user for security
RUN addgroup -g 1001 -S locksync && \
    adduser -S locksync -u 1001 -G locksync && \
    mkdir -p /app/data && \
    chown -R locksync:locksync /app
USER locksync

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD wget -qO- http://localhost:8080/health || exit 1

CMD ["node", "--max-old-space-size=192", "src/index.js"]
