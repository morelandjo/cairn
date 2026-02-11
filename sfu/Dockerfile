# Stage 1: Build
FROM node:24-alpine AS builder

RUN apk add --no-cache python3 make g++ linux-headers

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY tsconfig.json ./
COPY src src
RUN npm run build

# Prune dev dependencies
RUN npm prune --production

# Stage 2: Runtime
FROM node:24-alpine AS runtime

RUN apk add --no-cache curl \
  && addgroup -S murmuring \
  && adduser -S murmuring -G murmuring

WORKDIR /app

COPY --from=builder --chown=murmuring:murmuring /app/node_modules ./node_modules
COPY --from=builder --chown=murmuring:murmuring /app/dist ./dist
COPY --from=builder --chown=murmuring:murmuring /app/package.json ./

USER murmuring

ENV NODE_ENV=production
ENV PORT=4001

EXPOSE 4001

HEALTHCHECK --interval=15s --timeout=5s --retries=3 \
  CMD curl -sf http://localhost:4001/health || exit 1

CMD ["node", "dist/index.js"]
