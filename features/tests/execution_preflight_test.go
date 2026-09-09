package tests

import (
	"bytes"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
	"testing"

	"github.com/cucumber/godog"
)

func initPreflightScenarios(ctx *godog.ScenarioContext) {
	env := &ScenarioEnvironment{}
	result := &ScenarioRunResult{}
	state := &ScenarioState{
		env:    *env,
		result: *result,
	}

	////////////////////////////////////////////////////////////////////////////
	// Shared by all execution-preflight scenarios
	////////////////////////////////////////////////////////////////////////////
	ctx.Step(`^the FaradAI application starts$`, state.launchFaradAI)

	////////////////////////////////////////////////////////////////////////////
	// Shared by all failure-path execution-preflight scenarios
	////////////////////////////////////////////////////////////////////////////
	ctx.Step(`^it exits unsuccessfully$`, state.itExitsUnsuccessfully)

	////////////////////////////////////////////////////////////////////////////
	// Scenario: The container runtime is unavailable
	////////////////////////////////////////////////////////////////////////////
	ctx.Step(
		`^the required container runtime is not installed$`,
		state.createNoContainerRuntimeEnv,
	)
	ctx.Step(
		`^FaradAI reports that the container runtime is unavailable$`,
		state.reportsContainerRuntimeUnavailable,
	)

	////////////////////////////////////////////////////////////////////////////
	// Scenario: The container runtime is available but not ready
	////////////////////////////////////////////////////////////////////////////
	ctx.Step(
		`^the required container runtime is available but not ready$`,
		state.createNotReadyContainerRuntimeEnv,
	)
	ctx.Step(
		`^FaradAI reports that the container runtime is not ready$`,
		state.reportsContainerRuntimeNotReady,
	)
}

func TestContainerRuntimeValidationFeatures(t *testing.T) {
	suite := godog.TestSuite{
		ScenarioInitializer: initPreflightScenarios,
		Options: &godog.Options{
			TestingT: t,
			Paths:    []string{"../execution_preflight.feature"},
			Format:   "pretty",
		},
	}

	exitCode := suite.Run()

	if exitCode != 0 {
		t.Fatalf(
			"ContainerRuntimeValidationFeature suite failed with status %d",
			exitCode,
		)
	}
}

////////////////////////////////////////////////////////////////////////////////
// Shared by all execution-preflight scenarios
////////////////////////////////////////////////////////////////////////////////

type ScenarioEnvironment struct {
	path string
}

type ScenarioRunResult struct {
	stdout   string
	stderr   string
	exitCode int
}

type ScenarioState struct {
	env    ScenarioEnvironment
	result ScenarioRunResult
}

func (state *ScenarioState) launchFaradAI() error {
	faradaiCmd := exec.Cmd{
		Path: "../../faradai",
		Env:  append(os.Environ(), "PATH="+state.env.path),
	}

	var stdout, stderr bytes.Buffer

	faradaiCmd.Stdout = &stdout
	faradaiCmd.Stderr = &stderr

	err := faradaiCmd.Run()

	state.result.exitCode = 0
	if err != nil {
		if exitErr, ok := errors.AsType[*exec.ExitError](err); ok {
			state.result.exitCode = exitErr.ExitCode()
		} else {
			return fmt.Errorf("could not launch command: %w", err)
		}
	}

	state.result.stdout = stdout.String()
	state.result.stderr = stderr.String()

	return nil
}

////////////////////////////////////////////////////////////////////////////////
// Shared by all failure-path execution-preflight scenarios
////////////////////////////////////////////////////////////////////////////////

func (state *ScenarioState) itExitsUnsuccessfully() error {
	if state.result.exitCode == 0 {
		return fmt.Errorf(
			"expected a non-zero exit code but got %d",
			state.result.exitCode,
		)
	}

	return nil
}

////////////////////////////////////////////////////////////////////////////////
// Scenario: The container runtime is unavailable
////////////////////////////////////////////////////////////////////////////////

func (state *ScenarioState) createNoContainerRuntimeEnv() error {
	path, exists := os.LookupEnv("PATH")
	if !exists || path == "" {
		return errors.New(
			"PATH variable is missing or empty; ensure you are running the " +
				"tests in the Nix devShell environment",
		)
	}

	containerRuntimePath, err := exec.LookPath("podman")
	if err != nil {
		return fmt.Errorf(
			"unable to locate the container runtime in the Nix devShell: %w",
			err,
		)
	}

	containerRuntimeDir := filepath.Dir(containerRuntimePath)
	originalPathEntries := filepath.SplitList(path)
	newPathEntries := slices.DeleteFunc(
		originalPathEntries,
		func(pathSegment string) bool {
			cleanedPathSeg := filepath.Clean(pathSegment)

			return cleanedPathSeg == containerRuntimeDir ||
				!strings.HasPrefix(cleanedPathSeg, "/nix/store/")
		},
	)

	if len(originalPathEntries) == len(newPathEntries) {
		return errors.New(
			"failed to remove the container runtime tool from PATH",
		)
	}

	state.env.path = strings.Join(newPathEntries, string(os.PathListSeparator))

	return nil
}

func (state *ScenarioState) reportsContainerRuntimeUnavailable() error {
	const expected = `(?m)^faradai: [^\r\n]+ is not installed or not in PATH$`

	matched, err := regexp.MatchString(expected, state.result.stderr)

	if err != nil {
		return fmt.Errorf(
			"invalid regex matching pattern: %w",
			err,
		)
	}

	if !matched {
		return fmt.Errorf(
			"expected container runtime missing message was not detected; "+
				"received %q",
			state.result.stderr,
		)
	}

	return nil
}

////////////////////////////////////////////////////////////////////////////////
// Scenario: The container runtime is available but not ready
////////////////////////////////////////////////////////////////////////////////

func (state *ScenarioState) createNotReadyContainerRuntimeEnv() error {
	path, exists := os.LookupEnv("PATH")
	if !exists || path == "" {
		return errors.New(
			"PATH variable is missing or empty; ensure you are running the " +
				"tests in the Nix devShell environment",
		)
	}

	mockPodmanPath, err := filepath.Abs("system-mocks/podman-not-ready")
	if err != nil {
		return errors.New(
			"the podman mock's path for testing this scenario couldn't be" +
				"resolved",
		)
	}

	state.env.path = mockPodmanPath + string(os.PathListSeparator) + path

	return nil
}

func (state *ScenarioState) reportsContainerRuntimeNotReady() error {
	const expected = `(?m)^faradai: [^\r\n]+ is installed but not ready\.$`

	matched, err := regexp.MatchString(expected, state.result.stderr)

	if err != nil {
		return fmt.Errorf(
			"invalid regex matching pattern: %w",
			err,
		)
	}

	if !matched {
		return fmt.Errorf(
			"expected container runtime not ready message was not detected; "+
				"received %q",
			state.result.stderr,
		)
	}

	return nil
}
