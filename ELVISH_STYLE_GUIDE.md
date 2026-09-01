# FaradAI Elvish Style Guide

This guide applies to post-install and maintenance scripts. Elvish is chosen for explicit behavior and first-class BSD portability, not to reproduce Bash idioms.

## File structure and formatting

- Use the `.elv` extension and `#!/usr/bin/env elvish` only for directly executable scripts.
- Put imports first, followed by the strict command-resolution pragma, external bindings, constants/configuration, functions, then the entry flow.
- Indent blocks with two spaces. Keep one pipeline per line unless a short sequence is clearer together.
- Use `kebab-case` for functions and variables. Prefix module-private names with `-`.
- Comments explain security constraints, platform differences, or non-obvious intent; do not narrate each command.

## Command resolution

Every FaradAI script must disable implicit external-command resolution:

```elvish
pragma unknown-command = disallow
```

- Invoke occasional external commands explicitly through `e:`, such as `e:podman`.
- When an external is used repeatedly, bind it explicitly after the pragma:

  ```elvish
  var podman~ = $e:podman~
  ```

- Never depend on aliases, interactive `rc.elv`, or ambient command shadowing.
- Use Elvish builtins and standard modules before external `sed`, `grep`, `awk`, `find`, `date`, or platform-specific utilities.

## Values, variables, and arguments

- Use value pipelines, lists, and maps instead of parsing formatted text.
- Declare with `var`, mutate with `set`, and use `tmp` for lexical overrides.
- Environment variables always use the `E:` namespace. Use `has-env` or `get-env` when unset and empty have different meanings.
- Keep command arguments as lists and expand them with `$@args`. Never join arguments into a command string for re-evaluation.
- Use single quotes for literal strings. Remember that double-quoted strings support escapes but not interpolation; concatenate values explicitly.
- Use typed booleans `$true` and `$false`, not string conventions such as `0`/`1`, within Elvish code.

## Functions and modules

- Use Elvish built-in and standard-library modules only unless a concrete requirement justifies a third-party package. FaradAI currently has no `epm` dependencies.
- If a third-party package becomes necessary, record its repository and immutable commit in this guide before adding installation automation; `epm` has no central registry or lockfile.

- Give each function one visible responsibility and pass dependencies as arguments when doing so improves testing.
- Return data through value output with `put`; reserve byte output for user-facing text or external command pipelines.
- Use modules for shared behavior only after a second script needs it. Module filenames and namespaces should match.
- Avoid top-level side effects in reusable modules and avoid circular imports.

## Failure and cleanup

- Let unexpected exceptions stop the script. Use `try`/`catch` only to add context, perform a documented recovery, or translate an expected failure.
- Never catch and discard an exception silently.
- Validate paths, configuration, and command availability before making changes.
- Make cleanup explicit and idempotent. Do not remove a path derived from an unset variable, wildcard, or unvalidated command output.
- Preserve external exit failures. If several steps must succeed, rely on Elvish exception flow rather than Bash-style `set -e` emulation.

## Portability and security

- Target Linux, macOS, and FreeBSD behavior supported by Elvish. Gate unavoidable platform differences using the `platform` module.
- Do not assume GNU command flags, `/proc`, systemd, a particular home path, or a writable system directory.
- Pass secrets through files, descriptors, or Podman secret mounts, never command-line text or debug output.
- Quote or structurally preserve all paths and user-controlled values; never evaluate generated Elvish source.
- Prompts that authorize mounts, credentials, networking, devices, or ports must default to denial and fail closed when non-interactive.

## Verification

- Apply repository formatting defaults from `.editorconfig`; Elvish uses two-space indentation.
- Compile-check every script with `elvish -compileonly script.elv`.
- Use the built-in `elvish -lsp` language server for editor diagnostics. Elvish has no maintained standalone linter comparable to ShellCheck; do not substitute a Bash linter for Elvish syntax.
- Use the shared Cucumber/Gherkin features under `features/` for user-visible behavior. Godog step definitions may execute Elvish support scripts as black boxes; do not create a separate Elvish feature suite describing the same application contract.
- Use Bats for Elvish unit and component tests. Invoke public script commands or load a focused `.elv` module in a clean Elvish process, then assert status, byte output, value serialization, filesystem effects, and cleanup.
- Do not use Elvish upstream's `.elvts` transcript harness for FaradAI. It is a Go-based facility for testing the Elvish implementation and modules, not a standalone Elvish test runner. Reconsider only if Elvish publishes a maintained user-facing runner.
- Test success, validation failure, external-command failure, interruption, and idempotent cleanup paths.
- Keep fixtures self-contained and use temporary directories; tests must not depend on the user's `rc.elv` or mutate real container state unless explicitly integration-scoped.
- Keep Gherkin at the application-contract level and Bats at the script/module level. Do not duplicate cases without a distinct regression boundary.

## Sources

- [Elvish language reference](https://elv.sh/ref/language.html)
- [Elvish scripting case studies](https://elv.sh/learn/scripting-case-studies.html)
- [Elvish source conventions](https://github.com/elves/elvish)
- [Elvish testing documentation](https://github.com/elves/elvish/blob/main/docs/testing.md)
- [Bats-core](https://github.com/bats-core/bats-core)
- [Cucumber Gherkin reference](https://cucumber.io/docs/gherkin/reference/) and [Godog](https://github.com/cucumber/godog)
