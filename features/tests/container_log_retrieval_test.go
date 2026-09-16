package tests

import (
	"fmt"
	"os"
	"os/exec"
	"strings"
	"testing"

	"github.com/cucumber/godog"
)

func initContainerLogRetrievalFeatures(ctx *godog.ScenarioContext) {
	state := &containerLogsState{}

	ctx.Step(
		`^there is a running default FaradAI container named faradai$`,
		state.createRunningDefaultContainerEnv,
	)
	ctx.Step(
		`^there are no default FaradAI containers named faradai$`,
		state.createNoRunningContainersEnv,
	)
	ctx.Step(
		`^there is a running FaradAI container with a customized name$`,
		state.createRunningCustomContainerEnv,
	)
	ctx.Step(
		`^there is a running default FaradAI container but not a custom named one$`,
		state.createRunningDefaultContainerEnv,
	)
	ctx.Step(
		`^the logs are requested and no container name is given$`,
		state.requestLogsFromDefaultContainer,
	)
	ctx.Step(
		`^the logs are requested and the custom container name suffix is given$`,
		state.requestLogsFromCustomContainer,
	)
	ctx.Step(
		`^logs are requested with the option "--tail 1"$`,
		state.requestLastLineOfLogsFromContainer,
	)
	ctx.Step(
		`^FaradAI prints the logs for the default faradai container to stdout$`,
		state.printsDefaultContainerLogs,
	)
	ctx.Step(
		`^FaradAI prints a no such container message to stderr for the default container$`,
		state.printsNoSuchDefaultContainerErr,
	)
	ctx.Step(
		`^FaradAI prints a no such container message to stderr for the custom container$`,
		state.printsNoSuchCustomContainerErr,
	)
	ctx.Step(
		`^FaradAI prints the logs for the custom-named container to stdout$`,
		state.printsCustomContainerLogs,
	)
	ctx.Step(
		`^FaradAI prints only the last line of the container logs$`,
		state.printsOnlyLastLineOfLogs,
	)
	ctx.Step(
		`^returns 0 for the exit code$`,
		state.returnsExitCodeZero,
	)
	ctx.Step(
		`^returns a non-zero exit code$`,
		state.returnsExitCodeNonzero,
	)
}

func TestContainerLogRetrievalFeatures(t *testing.T) {
	requireContainerLogsContract(t)

	suite := godog.TestSuite{
		ScenarioInitializer: initContainerLogRetrievalFeatures,
		Options: &godog.Options{
			TestingT: t,
			Paths:    []string{"../container_log_retrieval.feature"},
			Format:   "pretty",
		},
	}

	exitCode := suite.Run()

	if exitCode != 0 {
		t.Fatalf(
			"ContainerLogRetrievalFeatures suite failed with status %d",
			exitCode,
		)
	}
}

////////////////////////////////////////////////////////////////////////////////
// Shared by all local scenarios
////////////////////////////////////////////////////////////////////////////////

type containerLogsEnvironment struct {
	path             string
	runningContainer string
}

type containerLogsState struct {
	env    containerLogsEnvironment
	result RunResult
}

const mockContainerLogsPodmanRelativePath = "system-mocks/container-logs-retrieval"

func (state *containerLogsState) createRunningDefaultContainerEnv() error {
	mockPath, err :=
		prependMockPodmanToPATH(mockContainerLogsPodmanRelativePath)
	if err != nil {
		return err
	}

	state.env.path = mockPath
	state.env.runningContainer = DefaultContainerName

	return nil
}

func (state *containerLogsState) createNoRunningContainersEnv() error {
	mockPath, err :=
		prependMockPodmanToPATH(mockContainerLogsPodmanRelativePath)
	if err != nil {
		return err
	}

	state.env.path = mockPath
	state.env.runningContainer = ""

	return nil
}

func (state *containerLogsState) createRunningCustomContainerEnv() error {
	mockPath, err :=
		prependMockPodmanToPATH(mockContainerLogsPodmanRelativePath)
	if err != nil {
		return err
	}

	state.env.path = mockPath
	state.env.runningContainer = CustomContainerName

	return nil
}

func (state *containerLogsState) buildFaradaiCmd() *exec.Cmd {
	return &exec.Cmd{
		Path: FaradaiRelativePath,
		Env: append(
			os.Environ(),
			"PATH="+state.env.path,
			"RUNNING_CONTAINER="+state.env.runningContainer,
		),
		Args: []string{FaradaiRelativePath},
	}
}

func (state *containerLogsState) requestLogsFromDefaultContainer() error {
	faradaiCmd := state.buildFaradaiCmd()

	faradaiCmd.Args = append(faradaiCmd.Args, "logs")

	state.result = runCmd(faradaiCmd)
	if state.result.error != nil {
		return state.result.error
	}

	return nil
}

func (state *containerLogsState) requestLogsFromCustomContainer() error {
	faradaiCmd := state.buildFaradaiCmd()

	faradaiCmd.Args =
		append(faradaiCmd.Args, "-n", CustomContainerSuffix, "logs")

	state.result = runCmd(faradaiCmd)
	if state.result.error != nil {
		return state.result.error
	}

	return nil
}

func (state *containerLogsState) requestLastLineOfLogsFromContainer() error {
	faradaiCmd := state.buildFaradaiCmd()

	faradaiCmd.Args =
		append(faradaiCmd.Args, "logs", "--tail", "1")

	state.result = runCmd(faradaiCmd)
	if state.result.error != nil {
		return state.result.error
	}

	return nil
}

func buildExpectedLogsMsg(containerName string) string {
	return containerName + ": first line of the logs\n" +
		containerName + ": the last line of the logs\n"
}

func (state *containerLogsState) matchLogs(expectedLogs string) error {
	if state.result.stdout != expectedLogs {
		return fmt.Errorf(
			"expected faradai logs to return:\n%q\n"+
				"But got:\n%q\nstderr:\n%q\nexit code: %d",
			expectedLogs,
			state.result.stdout,
			state.result.stderr,
			state.result.exitCode,
		)
	}

	return nil
}

func (state *containerLogsState) printsDefaultContainerLogs() error {
	return state.matchLogs(buildExpectedLogsMsg(DefaultContainerName))
}

func (state *containerLogsState) printsCustomContainerLogs() error {
	return state.matchLogs(buildExpectedLogsMsg(CustomContainerName))
}

func (state *containerLogsState) printsOnlyLastLineOfLogs() error {
	fullLogs := buildExpectedLogsMsg(DefaultContainerName)
	splitLogs := strings.Split(fullLogs, "\n")
	numLogsLines := len(splitLogs)

	if numLogsLines < 2 {
		return fmt.Errorf(
			"splitting the logs by line produced a smaller array than expected"+
				"\nFull Logs:\n%q",
			fullLogs,
		)
	}

	return state.matchLogs(splitLogs[numLogsLines-2] + "\n")
}

// Determines if the containerLogsState.result.stderr contains the strings
// provided by `expectedErrs` and returns an error if any of the substrings
// weren't found with the state.result information embedded in the error message
func (state *containerLogsState) matchErr(expectedErrs ...string) error {
	return matchTermOutput(
		Stderr,
		state.result.stdout,
		state.result.stderr,
		state.result.exitCode,
		expectedErrs...,
	)
}

func (state *containerLogsState) printsNoSuchDefaultContainerErr() error {
	return state.matchErr("no such container", DefaultContainerName)
}

func (state *containerLogsState) printsNoSuchCustomContainerErr() error {
	return state.matchErr("no such container", CustomContainerName)
}

func (state *containerLogsState) returnsExitCodeZero() error {
	return checkZeroExitCode(
		state.result.exitCode,
		state.result.stdout,
		state.result.stderr,
	)
}

func (state *containerLogsState) returnsExitCodeNonzero() error {
	return checkNonzeroExitCode(
		state.result.exitCode,
		state.result.stdout,
		state.result.stderr,
	)
}
