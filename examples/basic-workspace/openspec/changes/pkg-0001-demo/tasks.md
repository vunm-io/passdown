## 1. Implementation

- [ ] 1.1 Create the greet command module [dispatch: external-ok]
  - Paths: src/commands/greet.js
  - Done criteria: exports a `greet(name, { shout })` function returning the
    formatted string; throws if `name` is empty
  - Verification: `node -e "console.log(require('./src/commands/greet').greet('Alice'))"` prints `Hello, Alice!`

- [ ] 1.2 Register the subcommand in the CLI entrypoint [dispatch: external-ok]
  - Paths: src/cli.js
  - Done criteria: `demo-cli greet <name>` and `demo-cli greet <name> --shout`
    both route to `src/commands/greet.js`
  - Verification: `demo-cli greet Alice --shout` prints `HELLO, ALICE!`

## 2. Tests

- [ ] 2.1 Add unit tests for the greeting scenarios in the spec [dispatch: main]
  - Paths: test/commands/greet.test.js
  - Done criteria: covers basic greeting, shout variant, and missing-name error
    (matches the three scenarios in specs/demo-greeting/spec.md)
  - Verification: `npm test -- greet.test.js` passes
