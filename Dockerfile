# syntax=docker/dockerfile:1

# =========================================================
# 1) Build Web Admin + prepare static site
# =========================================================
FROM node:20-bookworm-slim AS frontend

WORKDIR /app

RUN corepack enable

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY apps/web-admin/package.json ./apps/web-admin/package.json

RUN pnpm install --frozen-lockfile

COPY . .

# Build React/Vite admin dashboard
RUN cd apps/web-admin && npm run build

# Build marketing HTML into marketing/site/
RUN node marketing/build.mjs

# Create the exact directory structure expected by Go:
#
# /app/site/index.html
# /app/site/styles.css
# /app/site/assets/...
# /app/site/admin/index.html
# /app/site/admin/assets/...
#
RUN mkdir -p /app/site \
    && cp -r /app/marketing/site/. /app/site/ \
    && mkdir -p /app/site/admin \
    && cp -r /app/apps/web-admin/dist/. /app/site/admin/


# =========================================================
# 2) Build Go backend
# =========================================================
FROM golang:1.26-bookworm AS backend

WORKDIR /app/apps/backend

COPY apps/backend/go.mod apps/backend/go.sum ./

RUN go mod download

COPY apps/backend ./

RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -o /server ./cmd/server


# =========================================================
# 3) Production image
# =========================================================
FROM debian:bookworm-slim

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates tzdata \
    && rm -rf /var/lib/apt/lists/*

COPY --from=backend /server /app/server
COPY --from=frontend /app/site /app/site

RUN mkdir -p /app/storage /app/logs

ENV PORT=8080
ENV STATIC_DIR=/app/site
ENV STORAGE_DIR=/app/storage
ENV LOG_DIR=/app/logs
ENV GIN_MODE=release
ENV APP_ENV=production

EXPOSE 8080

CMD ["/app/server"]
