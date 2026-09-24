# Container Dev Environment

Alternative to VS Code devcontainers for nf-neuro development. The Dockerfiles work with both Docker and Podman. The `dev` helper script uses Podman.

## Prerequisites

- [Podman](https://podman.io/) (for the `dev` script) or [Docker](https://docs.docker.com/get-docker/)

## Usage

```bash
# Prototyping (default) — includes scilus tools for manual work on modules in this repository
.dev/dev

# DevOps — includes CI tools (act, actionlint, nf-test, prettier)
.dev/dev devops

# Mount extra volumes
.dev/dev -v /data:/data

# Run one command and exit
.dev/dev bash -c 'nf-test test --profile apptainer,devcontainer,single_thread modules/nf-neuro/<category>/<tool>'
```

Both flavors can run the module tests, because the tests run the tools in apptainer containers.
The `prototyping` flavor here is not the same as `.devcontainer/prototyping`, which is for pipelines outside this repository.

## Persisted Data

The `dev` script keeps these in podman volumes between runs:

- `.venv` — the Python environment (`nf-neuro-<flavor>-venv`)
- `~/.cache` — apptainer images, the Nextflow runtime (`NXF_HOME`) and the test data archives (`NFNEURO_TEST_DATA_HOME`) (`nf-neuro-<flavor>-cache`)
- `.nextflow` — the Nextflow run history of the repository (`nf-neuro-<flavor>-nextflow`)

Test work folders go into `tests/.runs` in the repository on the host.

The script also sets `NFCORE_MODULES_*` and `NFCORE_SUBWORKFLOWS_*` so that `nf-core` commands use the nf-neuro repository.

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
nf-test test --profile apptainer,devcontainer,single_thread
```

Use the `single_thread` profile. CI uses it, and without it the md5 sums of multi-threaded tools do not match the snapshots.

## Installing Dependencies

```bash
poetry install --no-root
```

The environment is in `.venv`, which is on `PATH`, so `nf-core` and `pdiff` are available directly.

## Environment Variables

- `NF_NEURO_DEV_FLAVOR` — default flavor (`prototyping` or `devops`)
- `NF_NEURO_DEV_IMAGE` — override container image name
