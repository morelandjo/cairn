# Stage 1: Build
FROM elixir:1.19-otp-28-alpine AS builder

RUN apk add --no-cache build-base git vips-dev

WORKDIR /app

ENV MIX_ENV=prod

# Install hex + rebar
RUN mix local.hex --force && mix local.rebar --force

# Version (injected from git tag or VERSION file)
ARG APP_VERSION=dev
RUN echo "$APP_VERSION" > ../VERSION

# Copy dependency files first for caching
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mix deps.compile

# Copy application code
COPY config config
COPY lib lib
COPY priv priv

# Compile the app
RUN mix compile

# Build release
RUN mix release

# Stage 2: Runtime (must match builder's Alpine for OpenSSL compatibility)
FROM alpine:3.22 AS runtime

RUN apk add --no-cache \
  libstdc++ \
  openssl \
  ncurses-libs \
  vips \
  curl \
  && addgroup -S cairn \
  && adduser -S cairn -G cairn

WORKDIR /app

COPY --from=builder --chown=cairn:cairn /app/_build/prod/rel/cairn ./

# Create directories for runtime data
RUN mkdir -p /app/priv/uploads /app/priv/keys /app/priv/exports \
  && chown -R cairn:cairn /app

USER cairn

ENV PHX_SERVER=true
ENV PORT=4000

EXPOSE 4000

HEALTHCHECK --interval=15s --timeout=5s --retries=3 \
  CMD curl -sf http://localhost:4000/health || exit 1

CMD ["bin/cairn", "start"]
