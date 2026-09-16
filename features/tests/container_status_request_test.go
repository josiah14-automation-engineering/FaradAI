package tests

import (
	"os"
	"os/exec"
	"slices"
	"testing"

	"github.com/cucumber/godog"
)

func initContainerStatusRequestFeatures(ctx *godog.ScenarioContext) {
	state := &containerStatusState{}

	ctx.Step(
		`^the default FaradAI container named faradai exists and is running$`,
		state.createRunningDefaultContainerEnv,
	)
	ctx.Step(
		`^the custom FaradAI container named faradai-custom exists and is running$`,
		state.createRunningCustomContainerEnv,
	)
	ctx.Step(
		`^status is requested with no container name$`,
		state.requestStatusNoSuffix,
	)
	ctx.Step(
		`^status is requested with the container name suffix "custom"$`,
		state.requestStatusWithSuffix,
	)
	ctx.Step(
		`^FaradAI prints the name, state, start time, and image of container faradai to stdout$`,
		state.checkPrintsDefaultStatus,
	)
	ctx.Step(
		`^FaradAI prints the name, state, start time, and image of container faradai-custom to stdout$`,
		state.checkPrintsCustomStatus,
	)
	ctx.Step(
		`^FaradAI prints 'faradai' and  'not found' to stderr$`,
		state.checkPrintsDefaultNotFoundErr,
	)
	ctx.Step(
		`^FaradAI prints 'faradai-custom' and 'not found' to stderr$`,
		state.checkPrintsCustomNotFoundErr,
	)
	ctx.Step(
		`^FaradAI returns a non-zero exit code$`,
		state.checkNonzeroExitCode,
	)
	ctx.Step(
		`^FaradAI returns exit code 0$`,
		state.checkZeroExitCode,
	)
}

func TestContainerStatusRequestFeatures(t *testing.T) {
	requireContainerInspectContract(t)

	suite := godog.TestSuite{
		ScenarioInitializer: initContainerStatusRequestFeatures,
		Options: &godog.Options{
			TestingT: t,
			Paths:    []string{"../container_status_request.feature"},
			Format:   "pretty",
		},
	}

	exitCode := suite.Run()

	if exitCode != 0 {
		t.Fatalf(
			"ContainerStatusRequestFeatures suite failed with status %d",
			exitCode,
		)
	}
}

////////////////////////////////////////////////////////////////////////////////
// Shared by all local scenarios
////////////////////////////////////////////////////////////////////////////////

type containerStatusEnvironment struct {
	path             string
	runningContainer string
}

type containerStatusState struct {
	env    containerStatusEnvironment
	result RunResult
}

const mockContainerStatusPodmanRelativePath = "system-mocks/container-status-request"

func (state *containerStatusState) createRunningDefaultContainerEnv() error {
	mockPath, err :=
		prependMockPodmanToPATH(mockContainerStatusPodmanRelativePath)
	if err != nil {
		return err
	}

	state.env.path = mockPath
	state.env.runningContainer = DefaultContainerName

	return nil
}

func (state *containerStatusState) createRunningCustomContainerEnv() error {
	mockPath, err :=
		prependMockPodmanToPATH(mockContainerStatusPodmanRelativePath)
	if err != nil {
		return err
	}

	state.env.path = mockPath
	state.env.runningContainer = CustomContainerName

	return nil
}

func (state *containerStatusState) buildFaradaiCmd() *exec.Cmd {
	return &exec.Cmd{
		Path: FaradaiRelativePath,
		Env: append(
			os.Environ(),
			"PATH="+state.env.path,
			"RUNNING_CONTAINER="+state.env.runningContainer,
		),
		Args: []string{FaradaiRelativePath, "status"},
	}
}

func (state *containerStatusState) requestStatusNoSuffix() error {
	faradaiCmd := state.buildFaradaiCmd()

	state.result = runCmd(faradaiCmd)
	if state.result.error != nil {
		return state.result.error
	}

	return nil
}

func (state *containerStatusState) requestStatusWithSuffix() error {
	faradaiCmd := state.buildFaradaiCmd()

	faradaiCmd.Args =
		slices.Insert(faradaiCmd.Args, 1, "-n", CustomContainerSuffix)

	state.result = runCmd(faradaiCmd)
	if state.result.error != nil {
		return state.result.error
	}

	return nil
}

func (state *containerStatusState) checkPrintsDefaultStatus() error {
	expectedStatus :=
		`name:    ` + DefaultContainerName + `
state:   running
started: 2026-09-25T23:42:58.227595222Z
image:   faradai:latest`

	return matchTermOutput(
		Stdout,
		state.result.stdout,
		state.result.stderr,
		state.result.exitCode,
		expectedStatus,
	)
}

func (state *containerStatusState) checkPrintsCustomStatus() error {
	expectedStatus :=
		`name:    ` + CustomContainerName + `
state:   running
started: 2026-09-25T23:42:58.227595222Z
image:   faradai:latest`

	return matchTermOutput(
		Stdout,
		state.result.stdout,
		state.result.stderr,
		state.result.exitCode,
		expectedStatus,
	)
}

func (state *containerStatusState) checkPrintsDefaultNotFoundErr() error {
	return matchTermOutput(
		Stderr,
		state.result.stdout,
		state.result.stderr,
		state.result.exitCode,
		"not found",
		DefaultContainerName,
	)
}

func (state *containerStatusState) checkPrintsCustomNotFoundErr() error {
	return matchTermOutput(
		Stderr,
		state.result.stdout,
		state.result.stderr,
		state.result.exitCode,
		"not found",
		CustomContainerName,
	)
}

func (state *containerStatusState) checkNonzeroExitCode() error {
	return checkNonzeroExitCode(
		state.result.exitCode,
		state.result.stdout,
		state.result.stderr,
	)
}

func (state *containerStatusState) checkZeroExitCode() error {
	return checkZeroExitCode(
		state.result.exitCode,
		state.result.stdout,
		state.result.stderr,
	)
}
