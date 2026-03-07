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
    ca-certificates gnupg locales openssl \
    && locale-gen en_US.UTF-8 \
    && mkdir -p /run/sshd \
    && rm -rf /var/lib/apt/lists/*

# Node.js 22.x via NodeSource
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# GitHub CLI
RUN mkdir -p -m 755 /etc/apt/keyrings \
    && wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg \
       | tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
    && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
       | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# Go 1.23.x
RUN curl -fsSL https://go.dev/dl/go1.23.6.linux-amd64.tar.gz | tar -C /usr/local -xz
ENV PATH="/usr/local/go/bin:${PATH}"

# Create non-root user
RUN useradd -m -s /bin/bash -u 1000 coder \
    && echo "coder ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/coder \
    && chmod 0440 /etc/sudoers.d/coder

# Install opencode as coder user
USER coder
WORKDIR /home/coder
RUN curl -fsSL https://opencode.ai/install | bash
ENV PATH="/home/coder/.local/bin:${PATH}"

# Go path for coder
ENV GOPATH="/home/coder/go"
ENV PATH="${GOPATH}/bin:/usr/local/go/bin:${PATH}"

# Create directories for persistence
RUN mkdir -p /home/coder/.config/opencode \
    /home/coder/.local/share/opencode \
    /home/coder/.ssh \
    /home/coder/workspace

USER root
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 22

ENTRYPOINT ["/entrypoint.sh"]
