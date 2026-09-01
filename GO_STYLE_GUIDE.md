# FaradAI Go Style Guide

This guide applies to the Go CLI and Go tests. Prefer clear standard-library code over frameworks or speculative abstractions.

## Tooling

- Format every file with `gofmt`; use `goimports` when available to organize imports.
- Require `go tool -modfile=tools/go.mod golangci-lint run ./...`, `go vet ./...`, and `go test ./...` before merging. The checked-in `.golangci.yml` is the authoritative linter policy.
- Keep the module tidy with `go mod tidy`; add a dependency only when it is smaller and safer than maintaining the equivalent code.
- Keep application and test dependencies in the root `go.mod`. Keep Go-authored development executables in the isolated `tools/go.mod` so their dependency graphs cannot affect the FaradAI binary.
- Do not impose a manual line-length limit. Let `gofmt` decide layout and shorten code that remains hard to read.

## Packages and files

- Use short, lowercase, singular package names without underscores.
- Keep packages focused on one responsibility. Avoid catch-all names such as `util`, `common`, or `helpers`.
- Start with the fewest packages that keep dependencies one-directional. Use `internal/` only when an implementation must not become public API.
- Do not create interfaces until a real consumer needs substitution. Define small interfaces near the consumer, not the implementation.
- Avoid `init`; make setup and dependencies explicit.

## Names and documentation

- Use `MixedCaps`, not underscores. Keep initialisms consistent: `ID`, `URL`, `HTTP`, `OCI`.
- Prefer short names in small scopes and descriptive names at package boundaries. Receiver names should be one or two consistent letters.
- Export only what another package needs.
- Begin every exported declaration comment with the declaration's name. Explain purpose and constraints, not syntax visible in the code.

## Control flow and data

- Handle errors where they occur. Return early so the successful path stays unindented.
- Wrap errors with context using `%w`; inspect them with `errors.Is` or `errors.As`. Do not compare error text.
- Either return an error or log it at a process boundary; do not routinely do both.
- Use zero values when they are valid. Constructors should establish real invariants, not merely allocate a struct.
- Accept `context.Context` as the first parameter for work that can block or be cancelled. Do not store contexts in structs.
- Prefer synchronous code. Add goroutines only for actual concurrency, give each one an owner and termination path, and propagate cancellation.
- Pass slices, maps, and structs rather than unstructured `map[string]any` once data crosses a parsing boundary.

## FaradAI boundaries

- Parse TOML into typed structs, reject unknown keys, then validate all values before constructing Podman arguments.
- Keep resolution ordered and explicit: built-in defaults, user configuration, permitted project restrictions, invocation-specific arguments.
- Treat project configuration and container/image metadata as untrusted input.
- Build Podman commands as argument slices. Never construct a shell command string from configuration.
- Keep security-sensitive decisions—mount permissions, networking, devices, ports, credentials, capabilities—in named functions with direct tests.
- Use `os.UserConfigDir`, `os.UserHomeDir`, `filepath`, `os/exec`, and other standard-library platform APIs instead of invoking shell utilities.

## Testing

The project test stack is the standard `testing` package, Gomega, `go-cmp`, native fuzzing, Rapid, and Godog/Cucumber.

### Executable specifications

- Declare user-visible FaradAI behavior in Gherkin files under `features/`. A feature describes the application contract, regardless of whether a step exercises the Go CLI or an Elvish support script.
- Run features with the official [`godog`](https://github.com/cucumber/godog) package through a normal `TestFeatures(t *testing.T)` and `godog.Options{TestingT: t}`. Do not depend on the deprecated standalone Godog CLI.
- Write scenarios from the user's perspective. Cover security decisions, configuration precedence, lifecycle behavior, and failure recovery; leave internal branches and implementation details to unit tests.
- Keep steps small, reusable, and declarative. Step definitions adapt Gherkin to public commands; they must not reimplement application logic.
- Give every scenario isolated state, temporary directories, and unique container names. Scenario order must not matter, and concurrency must not corrupt shared state.
- A behavior change is incomplete until its feature is updated and executable. Do not duplicate the same case in Gherkin and unit tests unless the unit test protects a distinct low-level invariant.

### Go tests

- Use `testing` as the runner. Prefer table tests and subtests when cases share behavior, not merely to reduce line count.
- Call `t.Parallel()` only after confirming the test has no shared mutable process, environment, filesystem, port, or container state. Use `-parallel` and `-p` to control runner concurrency.
- Create Gomega per test with `g := NewWithT(t)`. Never use global `RegisterTestingT`; it is unsafe with parallel tests.
- Use ordinary Gomega matchers for readable assertions. Use `Eventually` and `Consistently` only for behavior that is genuinely asynchronous, always with a context or explicit timeout; never replace synchronization with arbitrary sleeps.
- Use `go-cmp` for semantic comparison or detailed structured diffs. Supply explicit `cmp.Option` values for ignored fields, ordering, tolerances, or equivalence.
- Use `testing.F` for coverage-guided fuzzing of TOML parsing, validation, names, paths, and argument construction. Seed the corpus with valid and boundary examples; a fuzz target must be deterministic and must not execute Podman.
- Use Rapid when a property needs rich generators, shrinking, or state-machine testing. Good properties include round trips, invariant preservation, deterministic resolution, and "project policy can restrict but never elevate user permissions."
- Prefer small handwritten fakes over generated mocks. Test observable behavior rather than call choreography.
- Put test fixtures in `testdata/`; use `t.TempDir`, `t.Setenv`, and `t.Cleanup` for isolation.

## Sources

- [Effective Go](https://go.dev/doc/effective_go)
- [Go Code Review Comments](https://go.dev/wiki/CodeReviewComments)
- [Google Go Style Guide](https://google.github.io/styleguide/go/)
- [`testing`](https://pkg.go.dev/testing) and [Go fuzzing](https://go.dev/doc/security/fuzz/)
- [Gomega](https://onsi.github.io/gomega/), [`go-cmp`](https://pkg.go.dev/github.com/google/go-cmp/cmp), and [Rapid](https://pgregory.net/rapid/)
- [Cucumber Gherkin reference](https://cucumber.io/docs/gherkin/reference/) and [Godog](https://github.com/cucumber/godog)
