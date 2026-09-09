Feature: Container runtime readiness validation
  Scenario: The container runtime is unavailable
    Given the required container runtime is not installed
    When the FaradAI application starts
    Then FaradAI reports that the container runtime is unavailable
    And it exits unsuccessfully

  Scenario: The container runtime is available but not ready
    Given the required container runtime is available but not ready
    When the FaradAI application starts
    Then FaradAI reports that the container runtime is not ready
    And it exits unsuccessfully
