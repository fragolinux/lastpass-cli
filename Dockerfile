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

# Final runtime image - use the builder image to avoid dependency mismatches
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# Install only essential runtime dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        curl \
        libxml2 \
        libssl3 \
        libcurl4 \
        bash \
        ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Install jq and yq if available, with graceful fallbacks
RUN apt-get update && \
    (apt-get install -y --no-install-recommends jq || true) && \
    rm -rf /var/lib/apt/lists/* && \
    # Create fallback scripts if packages are not available
    if ! command -v jq &> /dev/null; then \
        echo '#!/bin/bash' > /usr/local/bin/jq && \
        echo 'echo "jq not available" >&2 && exit 1' >> /usr/local/bin/jq && \
        chmod +x /usr/local/bin/jq; \
    fi && \
    if ! command -v yq &> /dev/null; then \
        echo '#!/bin/bash' > /usr/local/bin/yq && \
        echo 'echo "yq not available, use jq instead" >&2 && jq "$@"' >> /usr/local/bin/yq && \
        chmod +x /usr/local/bin/yq; \
    fi

# Copy the binary
COPY --from=builder /src/build/lpass /usr/local/bin/lpass

# Copy contrib folder with all scripts
COPY contrib/ /usr/local/share/lastpass-cli/contrib/

# Make scripts executable
RUN find /usr/local/share/lastpass-cli/contrib -name "*.sh" -exec chmod +x {} \;

# Create directories for volume mounts
RUN mkdir -p /backup /output /logs /data

# Set working directory
WORKDIR /data

# Default entrypoint - can be overridden
ENTRYPOINT ["/usr/local/bin/lpass"]

# Add a label for better identification
LABEL org.opencontainers.image.description="LastPass CLI with additional tools on Debian"
LABEL org.opencontainers.image.source="https://github.com/fragolinux/lastpass-cli"