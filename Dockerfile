# Multi-stage build: builder (Debian) + final (Debian)
FROM debian:bookworm-slim AS builder

ENV DEBIAN_FRONTEND=noninteractive

# Install build dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        cmake \
        pkg-config \
        libcurl4-openssl-dev \
        libxml2-dev \
        libssl-dev \
        ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Copy source code
WORKDIR /src
COPY . .

# Build binary
RUN mkdir -p build && \
    cd build && \
    cmake -DCMAKE_BUILD_TYPE=Release .. && \
    make -j$(nproc) && \
    strip lpass

# Final runtime image (Debian)
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# Install runtime tools and dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        jq \
        bash \
        ca-certificates \
        curl \
        libxml2 \
        openssl \
        keepassxc \
    && rm -rf /var/lib/apt/lists/*

# Install yq multiarch (usando curl invece di wget)
ARG YQ_VERSION="v4.46.1"
RUN set -e; \
    TARGETOS="linux"; \
    TARGETARCH="$(dpkg --print-architecture | sed 's/arm64/arm64/;s/amd64/amd64/;s/i386/386/')"; \
    YQ_BINARY="yq_${TARGETOS}_${TARGETARCH}"; \
    curl -sSL -o /usr/local/bin/yq "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/${YQ_BINARY}" && \
    chmod +x /usr/local/bin/yq

# Copy the binary
COPY --from=builder /src/build/lpass /usr/local/bin/lpass

# Copy contrib folder with all scripts
COPY contrib/ /usr/local/share/lastpass-cli/contrib/

# Make scripts executable
RUN find /usr/local/share/lastpass-cli/contrib -name "*.sh" -exec chmod +x {} \;

# Create directories for volume mounts
RUN mkdir -p /backup /output /logs /data

WORKDIR /data

ENTRYPOINT ["/usr/local/bin/lpass"]

LABEL org.opencontainers.image.description="LastPass CLI with additional tools (jq, yq, keepassxc-cli) on Debian Linux"
LABEL org.opencontainers.image.source="https://github.com/fragolinux/lastpass-cli"