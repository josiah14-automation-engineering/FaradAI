package tests

import (
	"bytes"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
)

type RunResult struct {
	stdout   string
	stderr   string
	exitCode int
	error    error
}

func getPATH() (string, error) {
	path, exists := os.LookupEnv("PATH")
	if !exists || path == "" {
		return "", errors.New(
			"PATH variable is missing or empty; ensure you are running the " +
				"tests in the Nix devShell environment",
		)
	}

	return path, nil
}

func matchString(expected string, actual string) (matched bool, err error) {
	matched, matchErr := regexp.MatchString(expected, actual)
	if matchErr != nil {
		return false, fmt.Errorf("invalid regex matching pattern: %w", matchErr)
	}

	return matched, nil
}

func runCmd(cmd *exec.Cmd) RunResult {
	var stdout, stderr bytes.Buffer
	cmdResult := RunResult{}

	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	err := cmd.Run()
	if err != nil {
		if exitErr, ok := errors.AsType[*exec.ExitError](err); ok {
			cmdResult.exitCode = exitErr.ExitCode()
		} else {
			cmdResult.error = fmt.Errorf("could not launch command: %w", err)
		}
	}
	cmdResult.stdout = stdout.String()
	cmdResult.stderr = stderr.String()

	return cmdResult
}

func getContainerRuntimePath() (string, error) {
	containerRuntimePath, err := exec.LookPath("podman")
	if err != nil {
		return "", fmt.Errorf(
			"unable to locate the container runtime in the Nix devShell: %w",
			err,
		)
	}

	return containerRuntimePath, nil
}

func getMockPodmanPath(relativePath string) (absolutePath string, err error) {
	mockPodmanPath, err := filepath.Abs(relativePath)
	if err != nil {
		return "", errors.New(
			"the podman mock's path for testing this scenario couldn't be " +
				"resolved",
		)
	}

	return mockPodmanPath, nil
}

func prependMockPodmanToPATH(mockRelativePath string) (path string, err error) {
	originalPath, err := getPATH()
	if err != nil {
		return "", err
	}

	mockPadmanAbsPath, err := getMockPodmanPath(mockRelativePath)
	if err != nil {
		return "", err
	}

	return mockPadmanAbsPath + string(os.PathListSeparator) + originalPath, nil
}
