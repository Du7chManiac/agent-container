FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# System packages + openssh-server
RUN apt-get update && apt-get install -y \
    openssh-server sudo git curl wget unzip build-essential \
    python3 python3-pip python3-venv \
    jq ripgrep fd-find tmux vim nano less htop \
    ca-certificates gnupg locales openssl tzdata \
    && locale-gen en_US.UTF-8 \
    && mkdir -p /run/sshd \
    && rm -rf /var/lib/apt/lists/*

# Node.js 22.x via NodeSource
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Native development libraries for common npm packages
RUN apt-get update && apt-get install -y \
    pkg-config \
    libsqlite3-dev \
    libpq-dev \
    libcairo2-dev \
    libjpeg-dev \
    libpango1.0-dev \
    libgif-dev \
    librsvg2-dev \
    libpixman-1-dev \
    libxml2-dev \
    libcurl4-openssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Global npm tools and configuration
RUN npm install -g node-gyp yarn pnpm \
    && npm cache clean --force \
    && npm config -g set fetch-timeout 300000 \
    && npm config -g set fetch-retries 5 \
    && npm config -g set fetch-retry-mintimeout 15000 \
    && npm config -g set fetch-retry-maxtimeout 120000

# OpenChamber web UI (optional alternative to opencode's built-in web — enable via OPENCODE_MODE=openchamber)
RUN npm install -g @openchamber/web@1.9.4 \
    && npm cache clean --force

# GitHub CLI
RUN mkdir -p -m 755 /etc/apt/keyrings \
    && wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg \
       | tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
    && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
       | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# Go 1.26.x (multi-arch)
RUN ARCH=$(dpkg --print-architecture) && \
    curl -fsSL "https://go.dev/dl/go1.26.1.linux-${ARCH}.tar.gz" | tar -C /usr/local -xz
ENV PATH="/usr/local/go/bin:${PATH}"

# Gitea tea CLI (multi-arch prebuilt binary)
ARG TEA_VERSION=0.11.0
RUN ARCH=$(dpkg --print-architecture) \
    && curl -fsSL "https://dl.gitea.com/tea/${TEA_VERSION}/tea-${TEA_VERSION}-linux-${ARCH}" \
         -o /usr/local/bin/tea \
    && chmod +x /usr/local/bin/tea

# Create non-root user
RUN userdel -r ubuntu 2>/dev/null || true \
    && useradd -m -s /bin/bash -u 1000 coder \
    && echo "coder ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/coder \
    && chmod 0440 /etc/sudoers.d/coder

# Install opencode as coder user
USER coder
WORKDIR /home/coder
RUN curl -fsSL https://opencode.ai/install | bash
ENV PATH="/home/coder/.opencode/bin:${PATH}"

# Go path for coder
ENV GOPATH="/home/coder/go"
ENV PATH="${GOPATH}/bin:/usr/local/go/bin:${PATH}"

# Create skeleton directory for first-boot home initialization
USER root
RUN mkdir -p /etc/skel.coder/.config/opencode \
    /etc/skel.coder/.local/share/opencode \
    /etc/skel.coder/.opencode/bin \
    /etc/skel.coder/.ssh \
    /etc/skel.coder/workspace \
    /etc/skel.coder/go \
    && cp -a /home/coder/.opencode/bin/opencode /etc/skel.coder/.opencode/bin/opencode
RUN cp -a /home/coder/.bashrc /etc/skel.coder/.bashrc 2>/dev/null || true \
    && cp -a /home/coder/.profile /etc/skel.coder/.profile 2>/dev/null || true

COPY entrypoint.sh /entrypoint.sh
COPY healthcheck.sh /healthcheck.sh
RUN chmod +x /entrypoint.sh /healthcheck.sh

EXPOSE 4096

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD /healthcheck.sh

ENTRYPOINT ["/entrypoint.sh"]
