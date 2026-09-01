# FaradAI Podman/OCI Container Style Guide

This guide applies to `Containerfile` authoring, image builds, and Podman runtime construction. Security boundaries take priority over Docker compatibility shortcuts.

## Naming and build context

- Name build definitions `Containerfile`; use `.containerignore` to keep credentials, VCS data, tests not needed by the build, and local artifacts out of the context.
- Build with Podman and request a fresh base image every time: `podman build --pull=always ...`.
- Use fully qualified base references with a release tag, for example `docker.io/library/ubuntu:24.04`. Do not use `latest`.
- Release tags are intentionally preferred over digest pins so routine rebuilds receive publisher security fixes. Rebuild regularly and retain the resulting image digest in release/build records for auditability.
- Pin downloaded tools and language dependencies to versions, and verify externally downloaded artifacts with a checksum or signature.

## Containerfile construction

- Use trusted, maintained base images and the smallest base that still provides the runtime behavior and debugging surface FaradAI actually needs.
- Use multi-stage builds so compilers, package managers, caches, and source trees do not enter the final image unless required at runtime.
- Order stable dependency steps before frequently changing application files to preserve useful build cache layers.
- Sort multi-line package lists. Combine package-index refresh, installation, and cache cleanup in one `RUN` instruction.
- Install no recommended or optional packages unless FaradAI uses them.
- Use `COPY`, not `ADD`, unless archive extraction is specifically intended. Set ownership during copy when supported instead of repairing it in another layer.
- Use exec-form `ENTRYPOINT` and `CMD` so signals reach the intended process and arguments are not interpreted by a shell.
- Use build secrets or secret mounts for credentials. Secrets must never appear in `ARG`, `ENV`, copied files, image history, or build logs.

## Image metadata and users

- Include OCI annotations for at least source, revision, version, licenses, title, description, and vendor when those values are known.
- Use `org.opencontainers.image.*` keys; do not invent keys inside the reserved `org.opencontainers` namespace.
- Create and run as a non-root image user. Give it only the directories and files it must write.
- Prefer numeric, stable UID/GID build arguments where host bind-mount ownership requires coordination; document the mapping.
- Do not bake credentials, host-specific configuration, mutable user state, or project source into the image.

## Podman runtime policy

- Run Podman rootless by default. A rootless container cannot gain more host privilege than its launching user.
- Never use `--privileged`. Start with all capabilities dropped and add back only a documented capability required by a tested workflow.
- Set `no-new-privileges`; keep the default seccomp and SELinux/AppArmor confinement unless a narrower reviewed profile replaces it.
- Never mount the Podman socket or another container-engine socket into the agent container.
- Default mounts to read-only. Writable mounts must have a named purpose, the narrowest possible source and destination, and explicit user approval when they expand host access.
- Default networking to the least access compatible with the selected mode. Publishing ports, host networking, devices, and SSH-agent forwarding require explicit policy and confirmation.
- Set memory, CPU, PID, and shared-memory limits explicitly. Use `--init` when the container's process tree needs a reaper.
- Keep containers ephemeral and managed by labels, not name-pattern guesses. Persistent state belongs in deliberate mounts, not the writable container layer.
- Use JSON/exec argument arrays in Go. Never pass user configuration through a shell or an unvalidated raw-argument escape hatch.

## Portability

- Produce and test both `linux/amd64` and `linux/arm64` images. Do not download an architecture-specific artifact without selecting and verifying the matching checksum.
- Treat Podman remote clients and native Podman hosts as distinct environments; do not assume host paths or sockets exist on the service host.
- Keep OCI-compatible image content, but document any Podman-specific runtime behavior instead of pretending it is portable.
- Use Quadlet only for persistent services. FaradAI's interactive ephemeral agent sessions should remain direct Podman invocations unless their lifecycle changes.

## Verification

- Lint `Containerfile` with the repository `.hadolint.yaml`; document narrowly scoped inline exceptions for intentional Podman-specific behavior.
- Build with a clean context and `--pull=always`, then run smoke tests against the resulting image without bind-mounted build overrides.
- Scan the built image with `go tool -modfile=tools/go.mod trivy image IMAGE`; the repository `trivy.yaml` makes high or critical vulnerabilities, misconfigurations, secrets, or license findings fail the check, including findings without a published fix.
- Inspect the image configuration and history for users, entrypoint, labels, layers, and accidental secrets.
- Exercise rootless startup, shutdown, signal handling, resource limits, read-only mounts, denied privilege escalation, and both supported architectures.
- Record the exact built image digest even though the source uses moving release tags.

## Sources

- [Podman documentation](https://docs.podman.io/en/latest/)
- [`podman build`](https://docs.podman.io/en/latest/markdown/podman-build.1.html) and [rootless Podman](https://github.com/containers/podman/blob/main/rootless.md)
- [OCI Image Specification](https://github.com/opencontainers/image-spec) and [OCI Runtime Specification](https://github.com/opencontainers/runtime-spec)
- [OCI annotation keys](https://github.com/opencontainers/image-spec/blob/main/annotations.md)
- [Container build best practices](https://docs.docker.com/build/building/best-practices/), used where the shared Containerfile format and OCI image model apply
