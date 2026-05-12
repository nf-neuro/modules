FROM docker.io/scilus/scilus:2.0.2

ARG NEXTFLOW_VERSION=24.10.5
ARG NFTEST_VERSION=0.9.3
ARG APPTAINER_VERSION=1.4.1
ARG POETRY_VERSION=1.8.5
ARG USERNAME=dev
ARG USER_UID=1000
ARG USER_GID=1000

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        gnupg \
        openjdk-17-jre \
        python3-venv \
        python3-pip \
        sudo \
        tmux \
        vim \
        wget \
        squashfs-tools \
        uidmap \
        fuse \
        fuse2fs \
    && rm -rf /var/lib/apt/lists/*

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

# pipx (system-wide) so the dev user can install poetry into ~/.local
RUN python3 -m pip install --no-cache-dir pipx

# Non-root user matching host UID (used with --userns=keep-id at runtime)
RUN groupadd --gid ${USER_GID} ${USERNAME} \
    && useradd --uid ${USER_UID} --gid ${USER_GID} -m -s /bin/bash ${USERNAME} \
    && echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME} \
    && chmod 0440 /etc/sudoers.d/${USERNAME}

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
