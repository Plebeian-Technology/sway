# syntax=docker/dockerfile:1

FROM golang:1.24-alpine AS builder

WORKDIR /app
COPY go.mod ./
COPY main.go ./

RUN --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /pdf-extractor .

FROM alpine:3.24

RUN --mount=type=cache,target=/var/cache/apk,sharing=locked \
    apk --cache-dir=/var/cache/apk -U add \
        mupdf-tools \
        tesseract-ocr \
        tesseract-ocr-data-eng \
        ca-certificates && \
    addgroup -S extractor && \
    adduser -S -G extractor extractor

ENV TESSDATA_PREFIX=/usr/share/tessdata
ENV OMP_THREAD_LIMIT=1
ENV PDF_EXTRACTOR_ALLOWED_ROOT=/rails/storage
ENV PORT=8085
ENV PDF_EXTRACTOR_CONCURRENCY=1

COPY --from=builder /pdf-extractor /pdf-extractor

USER extractor:extractor

EXPOSE 8085

ENTRYPOINT ["/pdf-extractor"]
