## Why

New users of `demo-cli` land on a blank prompt with no confirmation the tool
installed correctly. A one-line greeting command gives an immediate, scriptable
sanity check.

## What Changes

- Add a `greet <name>` subcommand that prints `Hello, <name>!` to stdout.
- Add a `--shout` flag that uppercases the greeting.

## Capabilities

### New Capabilities
- `demo-greeting`: prints a greeting for a given name, with an optional
  uppercase/shout variant.

### Modified Capabilities
(none — this is a new capability, no existing spec changes)

## Impact

- New file: `src/commands/greet.js`
- Modified: `src/cli.js` (register the new subcommand)
- No dependency changes, no data migration.
