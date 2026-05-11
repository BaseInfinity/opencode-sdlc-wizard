#!/usr/bin/env node
// validate-review-artifact.js — zero-dep JSON Schema validator for the
// .reviews/{handoff,response}.json artifacts shipped with this wizard.
//
// Implements the subset of draft-07 the schemas use:
//   type, required, properties, additionalProperties (bool only),
//   enum, pattern, minLength, minimum, items, $ref (#/definitions/*),
//   patternProperties, allOf with if/then, definitions.
//
// Usage:
//   node validate-review-artifact.js <artifact.json> <schema.json>
//
// Exit codes:
//   0 — artifact validates
//   1 — artifact fails validation (errors on stderr)
//   2 — usage / missing-file / unparseable JSON

'use strict';

const fs = require('fs');
const path = require('path');

function fail(code, msg) {
  process.stderr.write(msg + '\n');
  process.exit(code);
}

function readJson(filePath) {
  let raw;
  try {
    raw = fs.readFileSync(filePath, 'utf8');
  } catch (err) {
    fail(2, `cannot read ${filePath}: ${err.message}`);
  }
  try {
    return JSON.parse(raw);
  } catch (err) {
    fail(2, `cannot parse JSON in ${filePath}: ${err.message}`);
  }
}

function resolveRef(schema, ref) {
  if (!ref.startsWith('#/')) {
    throw new Error(`only local refs supported, got ${ref}`);
  }
  const parts = ref.slice(2).split('/');
  let cur = schema;
  for (const p of parts) {
    if (cur && Object.prototype.hasOwnProperty.call(cur, p)) {
      cur = cur[p];
    } else {
      throw new Error(`ref ${ref} could not be resolved`);
    }
  }
  return cur;
}

function typeOf(value) {
  if (value === null) return 'null';
  if (Array.isArray(value)) return 'array';
  if (Number.isInteger(value)) return 'integer';
  if (typeof value === 'number') return 'number';
  return typeof value;
}

function validate(value, schema, root, ptr, errors) {
  if (schema && schema.$ref) {
    schema = resolveRef(root, schema.$ref);
  }
  if (!schema) return;

  if (schema.type) {
    const t = typeOf(value);
    const expected = schema.type;
    const ok = expected === 'number' ? (t === 'number' || t === 'integer') : t === expected;
    if (!ok) {
      errors.push({ ptr, reason: `type mismatch: want ${expected}, got ${t}` });
      return;
    }
  }

  if (schema.enum && !schema.enum.includes(value)) {
    errors.push({ ptr, reason: `enum violation: ${JSON.stringify(value)} not in ${JSON.stringify(schema.enum)}` });
  }

  if (Object.prototype.hasOwnProperty.call(schema, 'const') && value !== schema.const) {
    errors.push({ ptr, reason: `const violation: ${JSON.stringify(value)} !== ${JSON.stringify(schema.const)}` });
  }

  if (typeof value === 'string') {
    if (typeof schema.minLength === 'number' && value.length < schema.minLength) {
      errors.push({ ptr, reason: `minLength violation: ${value.length} < ${schema.minLength}` });
    }
    if (schema.pattern) {
      const re = new RegExp(schema.pattern);
      if (!re.test(value)) {
        errors.push({ ptr, reason: `pattern violation: ${JSON.stringify(value)} does not match /${schema.pattern}/` });
      }
    }
  }

  if (typeof value === 'number' && typeof schema.minimum === 'number') {
    if (value < schema.minimum) {
      errors.push({ ptr, reason: `minimum violation: ${value} < ${schema.minimum}` });
    }
  }

  if (typeOf(value) === 'object') {
    if (Array.isArray(schema.required)) {
      for (const req of schema.required) {
        if (!Object.prototype.hasOwnProperty.call(value, req)) {
          errors.push({ ptr: `${ptr}/${req}`, reason: 'required field missing' });
        }
      }
    }
    const known = new Set(Object.keys(schema.properties || {}));
    const patternProps = schema.patternProperties || {};
    for (const [k, v] of Object.entries(value)) {
      const child = `${ptr}/${k}`;
      if (schema.properties && Object.prototype.hasOwnProperty.call(schema.properties, k)) {
        validate(v, schema.properties[k], root, child, errors);
        continue;
      }
      let matched = false;
      for (const [pattern, sub] of Object.entries(patternProps)) {
        if (new RegExp(pattern).test(k)) {
          validate(v, sub, root, child, errors);
          matched = true;
          break;
        }
      }
      if (matched) continue;
      // additionalProperties may be:
      //   false       — extra props forbidden
      //   true        — extra props allowed (default)
      //   {schema}    — extra props allowed but each must validate against the schema
      const ap = schema.additionalProperties;
      if (ap === false && !known.has(k)) {
        errors.push({ ptr: child, reason: 'additional property not allowed' });
      } else if (ap && typeof ap === 'object' && !Array.isArray(ap)) {
        validate(v, ap, root, child, errors);
      }
    }
  }

  if (Array.isArray(value) && schema.items) {
    value.forEach((item, i) => validate(item, schema.items, root, `${ptr}/${i}`, errors));
  }

  if (Array.isArray(schema.allOf)) {
    schema.allOf.forEach((sub, i) => {
      if (sub.if && sub.then) {
        const ifErrors = [];
        validate(value, sub.if, root, ptr, ifErrors);
        if (ifErrors.length === 0) {
          validate(value, sub.then, root, ptr, errors);
        }
      } else {
        validate(value, sub, root, ptr, errors);
      }
    });
  }
}

// Foreign-domain markers — top-level fields commonly seen in research,
// persuasion, and manuscript review handoffs but never in a code-review
// handoff. If the artifact carries one of these AND is missing several
// required code-review fields, the validator emits a DOMAIN HINT before the
// per-field errors so users don't read 5+ generic "required field missing"
// lines without knowing they may have passed the wrong schema.
//
// Caught during the states-project-research consumption test — the
// pre-existing handoff there described an interview-prep research review,
// not a code review, and the validator gave no signal that the schema
// might just be wrong for the artifact category.
const FOREIGN_DOMAIN_MARKERS = [
  'topic',
  'audience',
  'stakes',
  'research_question',
  'claim',
  'argument',
  'manuscript',
  'paper',
  'theme',
  'narrative',
];

function maybeDomainHint(artifact, schema, errors) {
  if (typeOf(artifact) !== 'object' || !Array.isArray(schema.required)) return null;
  const required = schema.required;
  const missingRequired = required.filter(
    (k) => !Object.prototype.hasOwnProperty.call(artifact, k)
  );
  if (missingRequired.length < 3) return null;
  const foreignPresent = FOREIGN_DOMAIN_MARKERS.filter((m) =>
    Object.prototype.hasOwnProperty.call(artifact, m)
  );
  if (foreignPresent.length === 0) return null;
  return (
    `DOMAIN HINT: artifact has foreign-domain fields (${foreignPresent.join(', ')}) ` +
    `and is missing ${missingRequired.length} required code-review fields ` +
    `(${missingRequired.join(', ')}). ` +
    `This may be a research/persuasion-domain handoff being validated against ` +
    `the code-review schema. Check that you're passing the right schema for the ` +
    `artifact category.`
  );
}

function main() {
  const argv = process.argv.slice(2);
  if (argv.length !== 2 || argv.includes('--help') || argv.includes('-h')) {
    fail(2, 'usage: validate-review-artifact.js <artifact.json> <schema.json>');
  }
  const [artifactPath, schemaPath] = argv;
  if (!fs.existsSync(artifactPath)) fail(2, `artifact not found: ${artifactPath}`);
  if (!fs.existsSync(schemaPath)) fail(2, `schema not found: ${schemaPath}`);
  const artifact = readJson(artifactPath);
  const schema = readJson(schemaPath);
  const errors = [];
  validate(artifact, schema, schema, '', errors);
  if (errors.length === 0) {
    process.stdout.write(`OK ${path.basename(artifactPath)} validates against ${path.basename(schemaPath)}\n`);
    process.exit(0);
  }
  const hint = maybeDomainHint(artifact, schema, errors);
  if (hint) {
    process.stderr.write(hint + '\n');
  }
  for (const e of errors) {
    process.stderr.write(`FAIL ${e.ptr || '/'} — ${e.reason}\n`);
  }
  process.exit(1);
}

main();
