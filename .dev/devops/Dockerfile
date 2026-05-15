FROM docker.io/ubuntu:24.04

ARG NODE_MAJOR=20
ARG ACTIONLINT_VERSION=1.7.7
ARG NEXTFLOW_VERSION=25.04.6
ARG NFTEST_VERSION=0.9.3

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        gnupg \
        jq \
        openjdk-17-jre-headless \
        python3 \
        shellcheck \
        software-properties-common \
        sudo \
        tmux \
        squashfs-tools \
        uidmap \
        fuse \
        fuse2fs \
    && add-apt-repository -y ppa:apptainer/ppa \
    && apt-get update \
    && apt-get install -y --no-install-recommends apptainer \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_MAJOR}.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid 1010 nodeusers \
    && mkdir -p -m 0775 /usr/local/lib/node_modules \
    && chown -R root:nodeusers /usr/local/lib/node_modules

RUN curl -fsSL https://raw.githubusercontent.com/nektos/act/master/install.sh | bash \
    && curl -fsSL "https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_linux_amd64.tar.gz" \
        | tar xz -C /usr/local/bin actionlint \
    && chmod u+x /usr/local/bin/actionlint

# GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# Nextflow
RUN curl -fsSL https://get.nextflow.io | NXF_VER=${NEXTFLOW_VERSION} bash \
    && mv nextflow /usr/local/bin/nextflow \
    && chmod u+x /usr/local/bin/nextflow

RUN npm install -g --save-exact prettier \
    && npm install -g editorconfig editorconfig-checker

COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

RUN usermod -aG nodeusers ubuntu \
    && echo "ubuntu ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ubuntu \
    && chmod u=r,g=r /etc/sudoers.d/ubuntu \
    && echo "prefix=/usr/local" >> /home/ubuntu/.npmrc

ENV PATH="/home/ubuntu/.local/bin:${PATH}"
ENV NXF_APPTAINER_CACHEDIR=/home/ubuntu/.cache/apptainer

USER ubuntu
WORKDIR /home/ubuntu

RUN mkdir -p .local/bin \
    && curl -fsSL https://code.askimed.com/install/nf-test | bash -s ${NFTEST_VERSION} \
    && mv nf-test /home/ubuntu/.local/bin/nf-test \
    && chmod u+x /home/ubuntu/.local/bin/nf-test

WORKDIR /workspace
CMD ["bash"]
