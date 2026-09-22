
# syntax=docker/dockerfile:1

# -------------------------
# 1. Build frontend
# -------------------------
FROM node:20-bookworm-slim AS frontend

WORKDIR /app

RUN corepack enable

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY apps/web-admin/package.json ./apps/web-admin/package.json

RUN pnpm install --frozen-lockfile

COPY . .

RUN cd apps/web-admin && npm run build
RUN node marketing/build.mjs

# Prepare everything the Go server will serve
RUN mkdir -p /app/site/admin \
    && cp -r /app/apps/web-admin/dist/. /app/site/admin/


# -------------------------
# 2. Build Go backend
# -------------------------
FROM golang:1.26-bookworm AS backend

WORKDIR /app/apps/backend

COPY apps/backend/go.mod apps/backend/go.sum ./
RUN go mod download

COPY apps/backend ./

RUN CGO_ENABLED=0 GOOS=linux go build -o /server ./cmd/server


# -------------------------
# 3. Production image
# -------------------------
FROM debian:bookworm-slim

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates tzdata \
    && rm -rf /var/lib/apt/lists/*

COPY --from=backend /server /app/server
COPY --from=frontend /app/site /app/site

ENV STATIC_DIR=/app/site
ENV GIN_MODE=release

EXPOSE 8080

CMD ["/app/server"]
