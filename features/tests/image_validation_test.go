package tests

import (
	"fmt"
	"os"
	"os/exec"
	"strings"
	"testing"

	"github.com/cucumber/godog"
)

func initImageValidationFeatures(ctx *godog.ScenarioContext) {
	state := &imageValidationState{}

	////////////////////////////////////////////////////////////////////////////
	// Given
	////////////////////////////////////////////////////////////////////////////
	ctx.Step(
		`^the faradai:latest image is unavailable$`,
		state.createImageUnavailableEnv,
	)
	ctx.Step(
		`^the faradai:latest image is available and lacks a username label value$`,
		state.createUsernamelessImageEnv,
	)
	ctx.Step(
		`^the faradai:latest image's username label doesn't match the system user$`,
		state.createMismatchedUsernameEnv,
	)
	ctx.Step(
		`^the faradai:latest image's username label and the system user match$`,
		state.createMatchingUsernameEnv,
	)
	////////////////////////////////////////////////////////////////////////////
	// When
	////////////////////////////////////////////////////////////////////////////
	ctx.Step(
		`^the faradai command is executed$`,
		state.runFaradAI,
	)
	////////////////////////////////////////////////////////////////////////////
	// Then & And
	////////////////////////////////////////////////////////////////////////////
	ctx.Step(
		`^FaradAI prints 'image not found' to stderr$`,
		state.printsImageNotFound,
	)
	ctx.Step(
		`^FaradAI accepts the image and continues execution$`,
		state.acceptsImageAndContinues,
	)
	ctx.Step(
		`^FaradAI prints a message containing the image and system usernames to stderr$`,
		state.printsUsernames,
	)
	ctx.Step(
		`^'install.sh' is mentioned in the stderr output$`,
		state.outputMentionsInstallScript,
	)
	ctx.Step(
		`^FaradAI returns a non-zero exit code$`,
		state.returnsNonZeroExitCode,
	)
}

func TestImageValidationFeatures(t *testing.T) {
	requireImageInspectContract(t)

	suite := godog.TestSuite{
		ScenarioInitializer: initImageValidationFeatures,
		Options: &godog.Options{
			TestingT: t,
			Paths:    []string{"../image_validation.feature"},
			Format:   "pretty",
		},
	}

	exitCode := suite.Run()

	if exitCode != 0 {
		t.Fatalf(
			"ImageValidationFeatures suite failed with status %d",
			exitCode,
		)
	}
}

////////////////////////////////////////////////////////////////////////////////
// Shared by all local scenarios
////////////////////////////////////////////////////////////////////////////////

type imageValidationEnvironment struct {
	path           string
	imageUser      string
	systemUser     string
	imageAvailable bool
}

type imageValidationState struct {
	env    imageValidationEnvironment
	result RunResult
}

const mockImageValidationPodmanRelativePath = "system-mocks/image-validation"
const mockFaradaiWorkdirPath = "force/failure/fake/path"
const defaultUser = "user"

// don't include defaultUser value as substring to avoid false positives from
// a strings.Contains check.
const mismatchUser = "mismatchusr"

////////////////////////////////////////////////////////////////////////////////
// Given
////////////////////////////////////////////////////////////////////////////////

func (state *imageValidationState) clearState() {
	state.env.imageAvailable = false
	state.env.imageUser = ""
	state.env.systemUser = ""
	state.env.path = ""
	state.result.exitCode = 0
	state.result.stdout = ""
	state.result.stderr = ""
}

func (state *imageValidationState) createImageUnavailableEnv() error {
	state.clearState()

	mockPath, err := prependMockPodmanToPATH(mockImageValidationPodmanRelativePath)
	if err != nil {
		return err
	}

	state.env.path = mockPath
	state.env.imageAvailable = false
	state.env.systemUser = defaultUser

	return nil
}

func (state *imageValidationState) createUsernamelessImageEnv() error {
	state.clearState()

	mockPath, err := prependMockPodmanToPATH(mockImageValidationPodmanRelativePath)
	if err != nil {
		return err
	}

	state.env.path = mockPath
	state.env.imageAvailable = true
	state.env.systemUser = defaultUser

	return nil
}

func (state *imageValidationState) createMismatchedUsernameEnv() error {
	state.clearState()

	mockPath, err := prependMockPodmanToPATH(mockImageValidationPodmanRelativePath)
	if err != nil {
		return err
	}

	state.env.path = mockPath
	state.env.imageAvailable = true
	state.env.systemUser = defaultUser
	state.env.imageUser = mismatchUser

	return nil
}

func (state *imageValidationState) createMatchingUsernameEnv() error {
	state.clearState()

	mockPath, err := prependMockPodmanToPATH(mockImageValidationPodmanRelativePath)
	if err != nil {
		return err
	}

	state.env.path = mockPath
	state.env.imageAvailable = true
	state.env.systemUser = defaultUser
	state.env.imageUser = defaultUser

	return nil
}

////////////////////////////////////////////////////////////////////////////////
// When
////////////////////////////////////////////////////////////////////////////////

func (state *imageValidationState) runFaradAI() error {
	imageAvailableStr := "no"
	if state.env.imageAvailable {
		imageAvailableStr = "yes"
	}

	// force the downstream function _resolve_workdir to fail by setting
	// FARADAI_WORKDIR to a false path to make checking the success path simple.
	faradaiCmd := exec.Cmd{
		Path: FaradaiRelativePath,
		Env: append(
			os.Environ(),
			"PATH="+state.env.path,
			"USER="+state.env.systemUser,
			"IMAGE_AVAILABLE="+imageAvailableStr,
			"IMAGE_USER="+state.env.imageUser,
			"FARADAI_WORKDIR="+mockFaradaiWorkdirPath,
		),
	}

	state.result = runCmd(&faradaiCmd)
	if state.result.error != nil {
		return state.result.error
	}

	return nil
}

////////////////////////////////////////////////////////////////////////////////
// Then & And
////////////////////////////////////////////////////////////////////////////////

func (state *imageValidationState) checkStderr(expected string) error {
	if state.result.stderr != expected {
		return fmt.Errorf(
			"expected faradai to produce stderr message:\n%q\n"+
				"But got:\nstdout:\n%q\nstderr:\n%q\nexit code: %d",
			expected,
			state.result.stdout,
			state.result.stderr,
			state.result.exitCode,
		)
	}

	return nil
}

func (state *imageValidationState) stderrContains(components []string) error {
	if !containsAllStr(state.result.stderr, components...) {
		return fmt.Errorf(
			"expected faradai to produce a stderr message containing:\n%s\n"+
				"But got:\nstdout:\n%q\nstderr:\n%q\nexit code: %d",
			strings.Join(components, "\n"),
			state.result.stdout,
			state.result.stderr,
			state.result.exitCode,
		)
	}

	return nil
}

func (state *imageValidationState) printsImageNotFound() error {
	return state.checkStderr(
		"faradai: image not found - run './install.sh' to build it\n",
	)
}

func (state *imageValidationState) acceptsImageAndContinues() error {
	return state.checkStderr(
		"faradai: FARADAI_WORKDIR '" + mockFaradaiWorkdirPath +
			"' does not exist or is not a directory\n",
	)
}

func (state *imageValidationState) printsUsernames() error {
	return state.stderrContains(
		[]string{state.env.imageUser, state.env.systemUser},
	)
}

func (state *imageValidationState) outputMentionsInstallScript() error {
	return state.stderrContains([]string{"./install.sh"})
}

func (state *imageValidationState) returnsNonZeroExitCode() error {
	return checkNonzeroExitCode(
		state.result.exitCode,
		state.result.stdout,
		state.result.stderr,
	)
}
