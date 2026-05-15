FROM docker.io/scilus/scilus:2.2.2

ARG NEXTFLOW_VERSION=25.04.6
ARG NFTEST_VERSION=0.9.3

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        gnupg \
        openjdk-17-jre \
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

COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

USER ubuntu
WORKDIR /home/ubuntu

ENV PATH="/home/ubuntu/.local/bin:${PATH}"
ENV NXF_APPTAINER_CACHEDIR=/home/ubuntu/.cache/apptainer

RUN mkdir -p .local/bin \
    && curl -fsSL https://code.askimed.com/install/nf-test | bash -s ${NFTEST_VERSION} \
    && mv nf-test /home/ubuntu/.local/bin/nf-test \
    && chmod u+x /home/ubuntu/.local/bin/nf-test

WORKDIR /workspace
CMD ["bash"]
