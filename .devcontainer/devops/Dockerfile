FROM python:3.12-slim-bookworm

ARG NFTEST_VERSION
ARG POETRY_VERSION
ARG USERNAME=neuro
ARG USER_UID=1000
ARG USER_GID=$USER_UID

ENV NODE_MAJOR=20
ENV ACTIONLINT_VERSION=1.7.7
ENV NFTEST_VERSION=${NFTEST_VERSION:-0.9.5}
ENV POETRY_VERSION=${POETRY_VERSION:-2.*}

RUN apt update && apt install -y \
        curl \
        git \
        jq \
        openjdk-17-jre \
        pipx \
        shellcheck \
        sudo \
        wget \
    && rm -rf /var/lib/apt/lists/*

# Install GitHub Actions testing and linting tools
RUN curl -fsSL https://raw.githubusercontent.com/nektos/act/master/install.sh | bash && \
    curl -fsSL https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_linux_amd64.tar.gz | \
    tar xz -C /usr/local/bin actionlint && \
    chmod +x /usr/local/bin/actionlint

# Install Node
#  - with user group nodeusers
#  - with global node_modules at /usr/local/lib/node_modules
# and create Yeoman user for vs-code extension publishing
#  - in group yeoman
#  - has sudoer rights without password (REQUIRED at container runtime)
#  - generates files in group owned /generated
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_MAJOR}.x | bash - &&\
    apt-get install -y nodejs && \
    groupadd --gid 501 yeoman && \
    groupadd --gid 1010 nodeusers && \
    useradd --uid 501 --gid yeoman --shell /bin/bash --create-home yeoman && \
    echo "yeoman ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers && \
    mkdir /generated && \
    chown yeoman:yeoman /generated && \
    mkdir -p -m 0775 /usr/local/lib/node_modules && \
    chown -R root:nodeusers /usr/local/lib/node_modules

# Install global npm tools in /usr/local and pre-download the editorconfig-checker binary
# (editorconfig-checker calls chmod on its binary at runtime, so USER_UID must own it)
RUN npm install -g --prefix /usr/local --save-exact prettier && \
    npm install -g --prefix /usr/local editorconfig editorconfig-checker@6 && \
    /usr/local/bin/editorconfig-checker --version && \
    chown -R ${USER_UID}:nodeusers /usr/local/lib/node_modules/editorconfig-checker

# Create neuro user inside the container
#  - in group neuro and nodeusers
#  - uses bash shell
#  - has sudoer rights without password (REQUIRED for container init lifecycle)
#  - sets its npm global prefix to /usr/local
RUN groupadd --gid $USER_GID $USERNAME && \
    useradd --uid $USER_UID --gid $USER_GID -m $USERNAME && \
    usermod -s /bin/bash -aG nodeusers $USERNAME && \
    echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME && \
    chmod 0440 /etc/sudoers.d/$USERNAME && \
    echo "prefix=/usr/local" >> /home/$USERNAME/.npmrc

# Set the user to use when running the image
USER $USERNAME

# Install Poetry using pipx in user environment
RUN pipx ensurepath && \
    pipx install poetry==${POETRY_VERSION}

# Export history for saving between container sessions
RUN SNIPPET="export PROMPT_COMMAND='history -a' && export HISTFILE=/home/$USERNAME/commandhistory/.bash_history" \
    && echo "$SNIPPET" >> "/home/$USERNAME/.bashrc"

ENTRYPOINT ["/bin/sh", "-lc", "pipx ensurepath && exec \"$@\""]
