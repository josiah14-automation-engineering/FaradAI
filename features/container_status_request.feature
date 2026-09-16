Feature: Container status request
  Scenario: Status requested for the default container
    Given the default FaradAI container named faradai exists and is running
    When status is requested with no container name
    Then FaradAI prints the name, state, start time, and image of container faradai to stdout
    And FaradAI returns exit code 0

  Scenario: Status requested for a custom-named container
    Given the custom FaradAI container named faradai-custom exists and is running
    When status is requested with the container name suffix "custom"
    Then FaradAI prints the name, state, start time, and image of container faradai-custom to stdout
    And FaradAI returns exit code 0

  Scenario: Default status requested when only a custom-named container exists
    Given only the custom FaradAI container named faradai-custom exists
    When status is requested with no container name
    Then FaradAI prints "container 'faradai' not found" to stderr
    And FaradAI returns a non-zero exit code

  Scenario: Custom status requested when only the default container exists
    Given only the default FaradAI container named faradai exists
    When status is requested with the container name suffix "custom"
    Then FaradAI prints "container 'faradai-custom' not found" to stderr
    And FaradAI returns a non-zero exit code
