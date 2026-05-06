FROM python:3.13-slim-bookworm

ARG NODE_MAJOR=20
ARG ACTIONLINT_VERSION=1.7.7
ARG NEXTFLOW_VERSION=24.10.5
ARG NFTEST_VERSION=0.9.3
ARG APPTAINER_VERSION=1.4.1
ARG POETRY_VERSION=2.0.1
ARG USERNAME=dev
ARG USER_UID=1000
ARG USER_GID=1000

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        gnupg \
        jq \
        openjdk-17-jre \
        pipx \
        shellcheck \
        sudo \
        tmux \
        wget \
        squashfs-tools \
        uidmap \
        fuse \
        fuse2fs \
    && rm -rf /var/lib/apt/lists/*

# Node (matches existing devops Dockerfile pattern)
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_MAJOR}.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid 1010 nodeusers \
    && mkdir -p -m 0775 /usr/local/lib/node_modules \
    && chown -R root:nodeusers /usr/local/lib/node_modules

# act + actionlint (matches existing)
RUN curl -fsSL https://raw.githubusercontent.com/nektos/act/master/install.sh | bash \
    && curl -fsSL "https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_linux_amd64.tar.gz" \
        | tar xz -C /usr/local/bin actionlint \
    && chmod +x /usr/local/bin/actionlint

# GitHub CLI (was ghcr.io/devcontainers/features/github-cli)
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# Apptainer (replaces ghcr.io/devcontainers/features/docker-in-docker)
RUN ARCH="$(dpkg --print-architecture)" \
    && curl -fsSL -o /tmp/apptainer.deb \
        "https://github.com/apptainer/apptainer/releases/download/v${APPTAINER_VERSION}/apptainer_${APPTAINER_VERSION}_${ARCH}.deb" \
    && apt-get update \
    && apt-get install -y --no-install-recommends /tmp/apptainer.deb \
    && rm -rf /var/lib/apt/lists/* /tmp/apptainer.deb

# Nextflow (was ghcr.io/robsyme/features/nextflow)
RUN curl -fsSL https://get.nextflow.io | NXF_VER=${NEXTFLOW_VERSION} bash \
    && mv nextflow /usr/local/bin/nextflow \
    && chmod 0755 /usr/local/bin/nextflow

# npm globals from onCreateCommand
RUN npm install -g --save-exact prettier \
    && npm install -g editorconfig editorconfig-checker

# Non-root user matching host UID (used with --userns=keep-id at runtime)
RUN groupadd --gid ${USER_GID} ${USERNAME} \
    && useradd --uid ${USER_UID} --gid ${USER_GID} -m -s /bin/bash -G nodeusers ${USERNAME} \
    && echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME} \
    && chmod 0440 /etc/sudoers.d/${USERNAME} \
    && echo "prefix=/usr/local" >> /home/${USERNAME}/.npmrc

ENV PATH="/home/${USERNAME}/.local/bin:${PATH}"
ENV NXF_APPTAINER_CACHEDIR=/home/${USERNAME}/.cache/apptainer

USER ${USERNAME}
WORKDIR /home/${USERNAME}

# nf-test installer drops nf-test.jar in ~/.nf-test/ and the wrapper in CWD; relocate wrapper onto PATH
RUN mkdir -p .local/bin \
    && curl -fsSL https://code.askimed.com/install/nf-test | bash -s ${NFTEST_VERSION} \
    && mv nf-test /home/${USERNAME}/.local/bin/nf-test \
    && chmod +x /home/${USERNAME}/.local/bin/nf-test

RUN pipx install poetry==${POETRY_VERSION}

WORKDIR /workspace
CMD ["bash"]
