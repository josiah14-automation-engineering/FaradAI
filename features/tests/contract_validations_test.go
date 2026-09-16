package tests

import (
	"fmt"
	"os/exec"
	"strings"
	"testing"
)

func requireContainerLogsContract(t *testing.T) {
	t.Helper()

	const containerName = "faradai-feature-specs-logs-contract-biskced"

	containerRuntimePath, err := getContainerRuntimePath()
	if err != nil {
		t.Fatal(err)
	}

	cmd := exec.Command(
		containerRuntimePath,
		"logs",
		"--tail",
		"1",
		containerName,
	)

	logsReqResult := runCmd(cmd)
	if logsReqResult.error != nil {
		t.Fatal(logsReqResult.error)
	}

	matched :=
		strings.Contains(
			strings.ToLower(logsReqResult.stderr),
			"no such container",
		) && strings.Contains(logsReqResult.stderr, containerName)

	if !matched || logsReqResult.exitCode == 0 {
		t.Fatal(
			fmt.Errorf(
				"Error: the logs retrieval contract for container runtime "+
					"executable doesn't match the expected interface.\n"+
					"cmd: %s\n"+
					"stdout:\n%s\n\n"+
					"stderr:\n%s\n\n"+
					"exit code: %d",
				cmd.String(),
				logsReqResult.stdout,
				logsReqResult.stderr,
				logsReqResult.exitCode,
			),
		)
	}
}

func requireContainerInspectContract(t *testing.T) {
	t.Helper()

	const containerName = "faradai-feature-specs-inspect-contract-thokb"

	containerRuntimePath, err := getContainerRuntimePath()
	if err != nil {
		t.Fatal(err)
	}

	cmd := exec.Command(
		containerRuntimePath,
		"inspect",
		"--type",
		"container",
		"--format",
		"$'name:    {{slice .Name 1}}'",
		containerName,
	)

	inspectReqResult := runCmd(cmd)
	if inspectReqResult.error != nil {
		t.Fatal(inspectReqResult.error)
	}

	matched :=
		strings.Contains(
			strings.ToLower(inspectReqResult.stderr),
			"no such container",
		) && strings.Contains(inspectReqResult.stderr, containerName)

	if !matched || inspectReqResult.exitCode == 0 {
		t.Fatal(
			fmt.Errorf(
				"Error: the inspect contract for container runtime "+
					"executable doesn't match the expected interface.\n"+
					"cmd: %s\n"+
					"stdout:\n%s\n\n"+
					"stderr:\n%s\n\n"+
					"exit code: %d",
				cmd.String(),
				inspectReqResult.stdout,
				inspectReqResult.stderr,
				inspectReqResult.exitCode,
			),
		)
	}
}
