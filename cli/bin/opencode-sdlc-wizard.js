#!/usr/bin/env node
'use strict';

// opencode-sdlc-wizard CLI entry point.
//
// Wraps the bundled `install.sh` so users can install via:
//   npx opencode-sdlc-wizard init
// instead of the longer
//   git clone https://github.com/BaseInfinity/opencode-sdlc-wizard /tmp/...
//   bash /tmp/.../install.sh
//
// Subcommands:
//   init [options]        Install the wizard into a target directory
//   check [options]       Check whether the installed wizard is up-to-date
//
// Init options pass through to install.sh:
//   --target-dir PATH     Default: cwd
//   --force               Overwrite existing customizations (default: keep)
//   --dry-run             Preview changes without writing
//
// Check options pass through to check-updates.sh:
//   --target-dir PATH     Default: cwd
//   --json                Machine-readable JSON output
//
// Top-level flags:
//   --help, -h            Show this help
//   --version, -v         Show version

const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const repoRoot = path.resolve(__dirname, '..', '..');
const pkg = JSON.parse(fs.readFileSync(path.join(repoRoot, 'package.json'), 'utf8'));
const installScript = path.join(repoRoot, 'install.sh');
const checkScript = path.join(repoRoot, 'scripts', 'check-updates.sh');
const pickScript = path.join(repoRoot, 'scripts', 'pick-backend.sh');

const args = process.argv.slice(2);

function printHelp() {
  process.stdout.write(`opencode-sdlc-wizard v${pkg.version}

Usage:
  npx opencode-sdlc-wizard init [options]    Install wizard into a target directory
  npx opencode-sdlc-wizard check [options]   Check whether the installed wizard is up-to-date
  npx opencode-sdlc-wizard pick [options]    Detect + configure a backend in one step
  npx opencode-sdlc-wizard --help            Show this help
  npx opencode-sdlc-wizard --version         Show version

init options (passed through to install.sh):
  --target-dir PATH    Directory to install into (default: cwd)
  --force              Overwrite existing customizations
  --dry-run            Preview changes; do not write

check options (passed through to check-updates.sh):
  --target-dir PATH    Directory to check (default: cwd)
  --json               Machine-readable JSON output
                       (exit 0 = current, 1 = behind, 2 = not installed)

After install:
  - AGENTS.md auto-loads on next OpenCode session
  - .opencode/plugins/sdlc-wizard.js subscribes to OpenCode events and
    fires the bash hooks at .opencode/hooks/
  - Run 'bash .opencode/scripts/detect-backends.sh' to see available
    backends, then 'bash .opencode/scripts/configure-backend.sh
    --tier <t> --provider <p> --model <m>' to pin one in opencode.json

See https://github.com/BaseInfinity/opencode-sdlc-wizard for full docs.
`);
}

if (args.includes('--help') || args.includes('-h')) {
  printHelp();
  process.exit(0);
}

if (args.includes('--version') || args.includes('-v')) {
  process.stdout.write(pkg.version + '\n');
  process.exit(0);
}

const subcommand = args.find((a) => !a.startsWith('-'));

if (!subcommand) {
  printHelp();
  process.exit(0);
}

if (subcommand === 'check') {
  // Pass remaining args (everything except the leading 'check') through
  // to scripts/check-updates.sh. Same env passes — including
  // CHECK_UPDATES_LATEST_OVERRIDE for tests.
  const checkArgs = args.filter((a, i) => !(a === 'check' && args.indexOf('check') === i));
  const result = spawnSync('bash', [checkScript, ...checkArgs], {
    stdio: 'inherit',
    cwd: process.cwd(),
    env: process.env,
  });
  if (result.error) {
    process.stderr.write(`Failed to run check-updates.sh: ${result.error.message}\n`);
    process.exit(2);
  }
  process.exit(result.status === null ? 1 : result.status);
}

if (subcommand === 'pick') {
  // v0.9.0: one-shot detect→configure. Pass remaining args through to
  // scripts/pick-backend.sh which orchestrates detect-backends.sh and
  // configure-backend.sh with a canonical default-model map per provider.
  const pickArgs = args.filter((a, i) => !(a === 'pick' && args.indexOf('pick') === i));
  const result = spawnSync('bash', [pickScript, ...pickArgs], {
    stdio: 'inherit',
    cwd: process.cwd(),
    env: process.env,
  });
  if (result.error) {
    process.stderr.write(`Failed to run pick-backend.sh: ${result.error.message}\n`);
    process.exit(2);
  }
  process.exit(result.status === null ? 1 : result.status);
}

if (subcommand !== 'init') {
  process.stderr.write(`Unknown subcommand: ${subcommand}\n\n`);
  printHelp();
  process.exit(2);
}

// Forward everything except the leading 'init' to install.sh. install.sh's own
// flag parser handles --target-dir, --force, --dry-run, --help passthrough.
const installArgs = args.filter((a, i) => !(a === 'init' && args.indexOf('init') === i));

// Dry-run: install.sh has no --dry-run flag itself yet, so we honor it at the
// wrapper layer by previewing what install.sh would do without actually
// running it. We approximate by listing the bundle files (REQUIRED_SOURCES)
// against the target. Full integration with install.sh's own dry-run would
// require teaching install.sh the flag — deferred to the next iteration.
if (installArgs.includes('--dry-run')) {
  // Find target dir from --target-dir or default to cwd
  let target = process.cwd();
  for (let i = 0; i < installArgs.length; i++) {
    if (installArgs[i] === '--target-dir' && installArgs[i + 1]) {
      target = installArgs[i + 1];
      break;
    }
    if (installArgs[i].startsWith('--target-dir=')) {
      target = installArgs[i].slice('--target-dir='.length);
      break;
    }
  }
  const required = [
    'AGENTS.md',
    'PRIVACY.md',
    '.opencode/plugins/sdlc-wizard.js',
    '.opencode/hooks/_find-sdlc-root.sh',
    '.opencode/hooks/sdlc-prompt-check.sh',
    '.opencode/hooks/tdd-pretool-check.sh',
    '.opencode/hooks/instructions-loaded-check.sh',
    '.opencode/hooks/model-effort-check.sh',
    '.opencode/hooks/precompact-seam-check.sh',
    '.opencode/scripts/detect-backends.sh',
    '.opencode/scripts/configure-backend.sh',
    '.opencode/skills/sdlc/SKILL.md',
    '.opencode/skills/setup-wizard/SKILL.md',
    '.opencode/skills/update-wizard/SKILL.md',
    '.opencode/skills/feedback/SKILL.md',
  ];
  process.stdout.write(`Dry run — install would create the following in ${target}:\n\n`);
  for (const f of required) {
    const dest = path.join(target, f);
    const status = fs.existsSync(dest) ? 'EXISTS' : 'CREATE';
    process.stdout.write(`  ${status}  ${f}\n`);
  }
  process.stdout.write('\nNo files written. Re-run without --dry-run to apply.\n');
  process.exit(0);
}

// Real run: invoke install.sh
const result = spawnSync('bash', [installScript, ...installArgs], {
  stdio: 'inherit',
  cwd: process.cwd(),
});

if (result.error) {
  process.stderr.write(`Failed to run install.sh: ${result.error.message}\n`);
  process.exit(1);
}

process.exit(result.status || 0);
