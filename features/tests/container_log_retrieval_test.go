package tests

import (
	"fmt"
	"os"
	"os/exec"
	"regexp"
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

const mockPodmanRelativePath = "system-mocks/container-logs-retrieval"
const defaultContainerName = "faradai"
const faradaiRelativePath = "../../faradai"
const customContainerSuffix = "custom"
const customContainerName = defaultContainerName + "-" + customContainerSuffix

func (state *containerLogsState) createRunningDefaultContainerEnv() error {
	mockPath, err := prependMockPodmanToPATH(mockPodmanRelativePath)
	if err != nil {
		return err
	}

	state.env.path = mockPath
	state.env.runningContainer = defaultContainerName

	return nil
}

func (state *containerLogsState) createNoRunningContainersEnv() error {
	mockPath, err := prependMockPodmanToPATH(mockPodmanRelativePath)
	if err != nil {
		return err
	}

	state.env.path = mockPath
	state.env.runningContainer = ""

	return nil
}

func (state *containerLogsState) createRunningCustomContainerEnv() error {
	mockPath, err := prependMockPodmanToPATH(mockPodmanRelativePath)
	if err != nil {
		return err
	}

	state.env.path = mockPath
	state.env.runningContainer = customContainerName

	return nil
}

func (state *containerLogsState) buildFaradaiCmd() *exec.Cmd {
	faradaiCmd := exec.Cmd{
		Path: faradaiRelativePath,
		Env: append(
			os.Environ(),
			"PATH="+state.env.path,
			"RUNNING_CONTAINER="+state.env.runningContainer,
		),
		Args: []string{faradaiRelativePath},
	}

	return &faradaiCmd
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
		append(faradaiCmd.Args, "-n", customContainerSuffix, "logs")

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
	return state.matchLogs(buildExpectedLogsMsg(defaultContainerName))
}

func (state *containerLogsState) printsCustomContainerLogs() error {
	return state.matchLogs(buildExpectedLogsMsg(customContainerName))
}

func (state *containerLogsState) printsOnlyLastLineOfLogs() error {
	fullLogs := buildExpectedLogsMsg(defaultContainerName)
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
	allMatched := true
	for _, expected := range expectedErrs {
		expPattern :=
			`(^|[^A-Za-z0-9_.-])` +
				regexp.QuoteMeta(expected) +
				`($|[[:space:].,:;"'])`
		matched, err := matchString(expPattern, state.result.stderr)
		if err != nil {
			return err
		}
		allMatched = allMatched && matched
	}

	if !allMatched {
		return fmt.Errorf(
			"expected msg was not received to stderr. Received:\n"+
				"stdout:\n%q\nstderr:\n%q\nexit code: %d\nmatch string:\n%q",
			state.result.stdout,
			state.result.stderr,
			state.result.exitCode,
			expectedErrs,
		)
	}

	return nil
}

func (state *containerLogsState) printsNoSuchDefaultContainerErr() error {
	return state.matchErr("no such container", defaultContainerName)
}

func (state *containerLogsState) printsNoSuchCustomContainerErr() error {
	return state.matchErr("no such container", customContainerName)
}

func (state *containerLogsState) returnsExitCodeZero() error {
	if state.result.exitCode != 0 {
		return fmt.Errorf(
			"expected exit code 0,but got: %d\nstdout:\n%q\nstderr:\n%q",
			state.result.exitCode,
			state.result.stdout,
			state.result.stderr,
		)
	}

	return nil
}

func (state *containerLogsState) returnsExitCodeNonzero() error {
	if state.result.exitCode == 0 {
		return fmt.Errorf(
			"expected Non-Zero exit code, but got: %d\n"+
				"stdout:\n%q\nstderr:\n%q",
			state.result.exitCode,
			state.result.stdout,
			state.result.stderr,
		)
	}

	return nil
}
