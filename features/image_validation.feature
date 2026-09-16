Feature: FaradAI OCI Image Validation
  Scenario: Required image is unavailable
    Given the faradai:latest image is unavailable
    When the faradai command is executed
    Then FaradAI prints 'image not found' to stderr
    And 'install.sh' is mentioned in the stderr output
    And FaradAI returns a non-zero exit code

  Scenario: Image lacks a username label value
    Given the faradai:latest image is available and lacks a username label value
    When the faradai command is executed
    Then FaradAI accepts the image and continues execution

  Scenario: Image username label doesn't match active system user
    Given the faradai:latest image's username label doesn't match the system user
    When the faradai command is executed
    Then FaradAI prints a message containing the image and system usernames to stderr
    And 'install.sh' is mentioned in the stderr output
    And FaradAI returns a non-zero exit code

  Scenario: Image username label and active system user match
    Given the faradai:latest image's username label and the system user match
    When the faradai command is executed
    Then FaradAI accepts the image and continues execution
