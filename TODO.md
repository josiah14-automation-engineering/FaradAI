# FaradAI — Open Items

## Security hardening

**`--cap-drop ALL` + `--security-opt no-new-privileges`** [HIGH]
The `docker run` in `faradai` uses default Docker capabilities (~14 Linux caps including `NET_RAW`, `SYS_CHROOT`). Adding `--cap-drop ALL` and `--security-opt no-new-privileges` would remove all capabilities the container doesn't need. Low-friction fix; high security value before open-sourcing.

**Env variable validation in `faradai` script** [MEDIUM]
`FARADAI_MEMORY`, `FARADAI_CPUS`, and `FARADAI_PIDS` are interpolated into `docker run` flags without validation. Add a regex check (e.g., `[0-9]+[kmg]?` for memory) to catch misconfiguration early and give the user a clear error.

---

## Design

**Non-atomic container lifecycle in `faradai`** [HIGH]
`docker rm -f` followed by `docker run` is not atomic. If the script is killed between steps, a stale or missing container remains with no cleanup. Add a `trap` to handle interrupts and ensure the container is always in a known state.

**Configurable project path** [MEDIUM]
`~/Development/personal` is hardcoded in `faradai`, `Dockerfile`, and `entrypoint.sh`. Replace with a `FARADAI_WORKDIR` environment variable so users can point the container at a different directory without editing scripts.

**Custom Docker flags passthrough** [MEDIUM]
No escape hatch for users who need extra volume mounts, ports, or env vars. A `FARADAI_DOCKER_ARGS` variable (split into array, appended to `docker run`) would allow customization without forking.

**Builder stage cache left in final image** [MEDIUM]
`pipx install` leaves pip, setuptools, and wheel in the venv. The final image copies the entire `~/.local` tree including cache. Clean up the builder's pipx cache before the `COPY --from=builder` step.

---

## Documentation

**Troubleshooting section in README** [MEDIUM]
Common failure modes — Docker permission denied, credential errors, SSH forwarding limitations, container name conflicts — have no documented resolution path.

**Upgrade/update instructions** [MEDIUM]
Users with an existing installation have no documented path to update the image or the `faradai` CLI script.

---

## Code quality

**`install.sh` missing `set -euo pipefail`** [LOW]
Every other script in the project has strict mode. `install.sh` alone does not — a failure mid-install could leave a corrupt binary at `/usr/local/bin/faradai`.

---

## Pre-open-source: community scaffolding

CONTRIBUTING.md, GitHub issue/PR templates, and a basic CI pipeline (shellcheck, hadolint, docker build smoke test). Deferred until the project is closer to publishing — premature for a personal tool in active development.
