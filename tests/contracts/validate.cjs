// Dev-only JSON Schema check for tests/contracts.sh. Never shipped.
// Usage: node validate.cjs <schema.json> <fixture.json>...
// Prints one line per fixture: <path>\t<valid|invalid|parse>\t<sorted,unique instancePaths>
'use strict';

const fs = require('fs');
const Ajv2020 = require('ajv/dist/2020').default;

const [schemaPath, ...files] = process.argv.slice(2);
const ajv = new Ajv2020({
  allErrors: true,
  strict: true,
  strictTypes: false,
  strictRequired: false,
});
const validate = ajv.compile(JSON.parse(fs.readFileSync(schemaPath, 'utf8')));

for (const file of files) {
  let data;
  try {
    data = JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (err) {
    console.log(`${file}\tparse\t`);
    continue;
  }
  if (validate(data)) {
    console.log(`${file}\tvalid\t`);
  } else {
    const paths = [...new Set(validate.errors.map((e) => e.instancePath))].sort();
    console.log(`${file}\tinvalid\t${paths.join(',')}`);
  }
}
