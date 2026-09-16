Feature: Container logs request
  Scenario: There is a running default FaradAI container
    Given there is a running default FaradAI container named faradai
    When the logs are requested and no container name is given
    Then FaradAI prints the logs for the default faradai container to stdout
    And returns 0 for the exit code

  Scenario: There are no default FaradAI containers
    Given there are no default FaradAI containers named faradai
    When the logs are requested and no container name is given
    Then FaradAI prints a no such container message to stderr for the default container
    And returns a non-zero exit code

  Scenario: No name is given when requesting logs from a custom-named FaradAI container
    Given there is a running FaradAI container with a customized name
    When the logs are requested and no container name is given
    Then FaradAI prints a no such container message to stderr for the default container
    And returns a non-zero exit code

  Scenario: Logs are requested from a non-running custom-named FaradAI container
    Given there is a running default FaradAI container but not a custom named one
    When the logs are requested and the custom container name suffix is given
    Then FaradAI prints a no such container message to stderr for the custom container
    And returns a non-zero exit code

  Scenario: Logs are requested from a custom-named FaradAI container
    Given there is a running FaradAI container with a customized name
    When the logs are requested and the custom container name suffix is given
    Then FaradAI prints the logs for the custom-named container to stdout
    And returns 0 for the exit code

  Scenario: Logs are requested with an option
    Given there is a running default FaradAI container named faradai
    When logs are requested with the option "--tail 1"
    Then FaradAI prints only the last line of the container logs
    And returns 0 for the exit code
