FROM alpine:3.22 AS builder

# Install build dependencies
RUN apk add --no-cache \
    build-base \
    cmake \
    pkgconfig \
    curl-dev \
    libxml2-dev \
    openssl-dev

# Copy source code
WORKDIR /src
COPY . .

# Build binary
RUN mkdir -p build && \
    cd build && \
    cmake -DCMAKE_BUILD_TYPE=Release .. && \
    make -j$(nproc) && \
    strip lpass

# Final runtime image
FROM alpine:3.22

# Add edge repositories for additional packages
RUN echo "https://dl-cdn.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories && \
    echo "https://dl-cdn.alpinelinux.org/alpine/edge/testing" >> /etc/apk/repositories

# Install runtime tools and dependencies
RUN apk add --no-cache \
    jq \
    yq \
    keepassxc \
    bash \
    ca-certificates \
    curl \
    libxml2 \
    openssl \
    && rm -rf /var/cache/apk/*

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
LABEL org.opencontainers.image.description="LastPass CLI with additional tools (jq, yq, keepassxc-cli) on Alpine Linux"
LABEL org.opencontainers.image.source="https://github.com/fragolinux/lastpass-cli"