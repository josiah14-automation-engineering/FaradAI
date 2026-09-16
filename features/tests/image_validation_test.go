package tests

import (
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
	path       string
	imageUser  string
	systemUser string
}

type imageValidationState struct {
	env    imageValidationEnvironment
	result RunResult
}

const mockImageValidationPodmanRelativePath = "system-mocks/image-validation"

////////////////////////////////////////////////////////////////////////////////
// Given
////////////////////////////////////////////////////////////////////////////////

func (state *imageValidationState) createImageUnavailableEnv() error {
	println(mockImageValidationPodmanRelativePath)
	return godog.ErrPending
}

func (state *imageValidationState) createUsernamelessImageEnv() error {
	return godog.ErrPending
}

func (state *imageValidationState) createMismatchedUsernameEnv() error {
	return godog.ErrPending
}

func (state *imageValidationState) createMatchingUsernameEnv() error {
	return godog.ErrPending
}

////////////////////////////////////////////////////////////////////////////////
// When
////////////////////////////////////////////////////////////////////////////////

func (state *imageValidationState) runFaradAI() error {
	return godog.ErrPending
}

func (state *imageValidationState) printsImageNotFound() error {
	return godog.ErrPending
}

func (state *imageValidationState) acceptsImageAndContinues() error {
	return godog.ErrPending
}

func (state *imageValidationState) printsUsernames() error {
	return godog.ErrPending
}

func (state *imageValidationState) outputMentionsInstallScript() error {
	return godog.ErrPending
}

func (state *imageValidationState) returnsNonZeroExitCode() error {
	return godog.ErrPending
}
