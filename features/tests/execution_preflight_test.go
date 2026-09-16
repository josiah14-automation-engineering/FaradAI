package tests

import (
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

func initPreflightScenarios(t *testing.T, ctx *godog.ScenarioContext) {
	state := &ScenarioState{}

	////////////////////////////////////////////////////////////////////////////
	// Shared by all failure-path execution-preflight scenarios
	////////////////////////////////////////////////////////////////////////////
	ctx.Step(`^the FaradAI application starts$`, state.launchFaradAI)
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
	// Scenario: The container runtime is available but NOT ready
	////////////////////////////////////////////////////////////////////////////
	ctx.Step(
		`^the required container runtime is available but not ready$`,
		state.createNotReadyContainerRuntimeEnv,
	)
	ctx.Step(
		`^FaradAI reports that the container runtime is not ready$`,
		state.reportsContainerRuntimeNotReady,
	)

	////////////////////////////////////////////////////////////////////////////
	// Scenario: The container runtime is available AND ready
	////////////////////////////////////////////////////////////////////////////
	ctx.Step(
		`^the required container runtime is available and ready$`,
		state.createAvailableContainerRuntimeEnv,
	)
	ctx.Step(
		`^the FaradAI container status is requested$`,
		func() error {
			requireContainerInspectContract(t)
			return state.requestFaradAIStatus()
		},
	)
	ctx.Step(
		`^FaradAI reaches the status reporting mechanism$`,
		state.reportsContainerStatus,
	)
}

func TestContainerRuntimeValidationFeatures(t *testing.T) {
	suite := godog.TestSuite{
		ScenarioInitializer: func(ctx *godog.ScenarioContext) {
			initPreflightScenarios(t, ctx)
		},
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
// Shared by all local scenarios
////////////////////////////////////////////////////////////////////////////////

type ScenarioEnvironment struct {
	path string
}

type ScenarioState struct {
	env    ScenarioEnvironment
	result RunResult
}

////////////////////////////////////////////////////////////////////////////////
// Shared by all failure-path execution-preflight scenarios
////////////////////////////////////////////////////////////////////////////////

func (state *ScenarioState) launchFaradAI() error {
	faradaiCmd := exec.Cmd{
		Path: "../../faradai",
		Env:  append(os.Environ(), "PATH="+state.env.path),
	}

	state.result = runCmd(&faradaiCmd)
	if state.result.error != nil {
		return state.result.error
	}

	return nil
}

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
	path, err := getPATH()
	if err != nil {
		return err
	}

	containerRuntimePath, err := getContainerRuntimePath()
	if err != nil {
		return err
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

	matched, err := matchString(expected, state.result.stderr)
	if err != nil {
		return err
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
// Scenario: The container runtime is available but NOT ready
////////////////////////////////////////////////////////////////////////////////

func (state *ScenarioState) createNotReadyContainerRuntimeEnv() error {
	newPath, err := prependMockPodmanToPATH("system-mocks/execution-preflight")
	if err != nil {
		return err
	}

	state.env.path = newPath

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

////////////////////////////////////////////////////////////////////////////////
// Scenario: The container runtime is available AND ready
////////////////////////////////////////////////////////////////////////////////

func (state *ScenarioState) createAvailableContainerRuntimeEnv() error {
	path, err := getPATH()
	if err != nil {
		return err
	}

	_, err = getContainerRuntimePath()
	if err != nil {
		return err
	}

	state.env.path = path

	return nil
}

func (state *ScenarioState) requestFaradAIStatus() error {
	faradaiCmd := exec.Cmd{
		Path: "../../faradai",
		Env:  append(os.Environ(), "PATH="+state.env.path),
		Args: []string{"../../faradai", "status"},
	}

	state.result = runCmd(&faradaiCmd)
	if state.result.error != nil {
		return state.result.error
	}

	return nil
}

func (state *ScenarioState) reportsContainerStatus() error {
	var expected string
	var actual string

	switch state.result.exitCode {
	case 0:
		expected = `(?m)^name:[ \t]+faradai(-\S+)?\r?\nstate:[ \t]+`
		actual = state.result.stdout
	case 1:
		expected = "(?m)^faradai: container 'faradai' not found"
		actual = state.result.stderr
	default:
		return fmt.Errorf(
			"received unexpected error code from faradai: %d\n%s\n%s",
			state.result.exitCode,
			state.result.stdout,
			state.result.stderr,
		)
	}

	matched, err := matchString(expected, actual)
	if err != nil {
		return err
	}

	if !matched {
		return fmt.Errorf(
			"expected faradai state message was not detected: received\n%q\n%q",
			state.result.stdout,
			state.result.stderr,
		)
	}

	return nil
}
