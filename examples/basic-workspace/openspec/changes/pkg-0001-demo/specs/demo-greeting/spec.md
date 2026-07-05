## ADDED Requirements

### Requirement: Greet a named user
The system SHALL print `Hello, <name>!` to stdout when run as
`demo-cli greet <name>`.

#### Scenario: Basic greeting
- **WHEN** the user runs `demo-cli greet Alice`
- **THEN** the CLI prints `Hello, Alice!` and exits with code 0

### Requirement: Shout variant
The system SHALL uppercase the entire greeting when the `--shout` flag is
passed.

#### Scenario: Shouted greeting
- **WHEN** the user runs `demo-cli greet Alice --shout`
- **THEN** the CLI prints `HELLO, ALICE!` and exits with code 0

#### Scenario: Missing name
- **WHEN** the user runs `demo-cli greet` with no name argument
- **THEN** the CLI prints a usage error to stderr and exits with a non-zero code
