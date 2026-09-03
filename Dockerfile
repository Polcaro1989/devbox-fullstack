FROM ubuntu:24.04 AS toolchain

ENV DEBIAN_FRONTEND=noninteractive \
    DOTNET_ROOT=/usr/share/dotnet \
    NVM_DIR=/home/dev/.nvm

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl wget git unzip zip xz-utils jq sudo \
    build-essential pkg-config libicu-dev libssl-dev zlib1g-dev \
    php-cli php-curl php-mbstring php-xml php-zip php-bcmath php-intl php-sqlite3 \
    composer \
    python3 python3-pip python3-venv \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash dev \
    && usermod -aG sudo dev \
    && echo 'dev ALL=(ALL) NOPASSWD:ALL' >/etc/sudoers.d/dev \
    && chmod 0440 /etc/sudoers.d/dev \
    && mkdir -p /workspace \
    && chown -R dev:dev /workspace /home/dev

RUN curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh \
    && chmod +x /tmp/dotnet-install.sh \
    && /tmp/dotnet-install.sh --channel 8.0 --install-dir /usr/share/dotnet --no-path \
    && /tmp/dotnet-install.sh --channel 9.0 --install-dir /usr/share/dotnet --no-path \
    && /tmp/dotnet-install.sh --channel 10.0 --install-dir /usr/share/dotnet --no-path \
    && ln -s /usr/share/dotnet/dotnet /usr/local/bin/dotnet \
    && rm -f /tmp/dotnet-install.sh

USER dev
RUN curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash \
    && bash -lc 'source "$HOME/.nvm/nvm.sh" && nvm install --lts && nvm alias default "lts/*"' \
    && printf '\nexport NVM_DIR="$HOME/.nvm"\n[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"\n' >> /home/dev/.bashrc

USER root
COPY scripts/verify-toolchain.sh /usr/local/bin/verify-toolchain
RUN chmod +x /usr/local/bin/verify-toolchain

USER dev
WORKDIR /workspace

FROM toolchain AS ssh-runtime

USER root
RUN apt-get update && apt-get install -y --no-install-recommends openssh-server \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /run/sshd /var/lib/devbox-ssh \
    && chmod 700 /var/lib/devbox-ssh \
    && printf '%s\n' \
       'PasswordAuthentication yes' \
       'PermitRootLogin no' \
       'PubkeyAuthentication yes' \
       'AllowUsers dev' \
       'UsePAM yes' \
       > /etc/ssh/sshd_config.d/99-devbox.conf

COPY entrypoint.sh /usr/local/bin/devbox-entrypoint
RUN chmod +x /usr/local/bin/devbox-entrypoint

WORKDIR /workspace
EXPOSE 22
ENTRYPOINT ["/usr/local/bin/devbox-entrypoint"]
