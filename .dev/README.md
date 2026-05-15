# Container Dev Environment

Alternative to VS Code devcontainers for nf-neuro development. The Dockerfiles work with both Docker and Podman. The `dev` helper script uses Podman.

## Prerequisites

- [Podman](https://podman.io/) (for the `dev` script) or [Docker](https://docs.docker.com/get-docker/)

## Usage

```bash
# Prototyping (default) — includes scilus tools
.dev/dev

# DevOps — includes CI tools (act, actionlint, nf-test, prettier)
.dev/dev devops

# Mount extra volumes
.dev/dev -v /data:/data
```

## Building Manually

```bash
# With Podman
podman build -t nf-neuro-prototyping .dev/prototyping/
podman build -t nf-neuro-devops .dev/devops/

# With Docker
docker build -t nf-neuro-prototyping .dev/prototyping/
docker build -t nf-neuro-devops .dev/devops/
```

## Running Tests

```bash
nf-test test --profile apptainer,devcontainer
```

## Installing Dependencies

```bash
uv sync --no-install-project
```

## Environment Variables

- `NF_NEURO_DEV_FLAVOR` — default flavor (`prototyping` or `devops`)
- `NF_NEURO_DEV_IMAGE` — override container image name
