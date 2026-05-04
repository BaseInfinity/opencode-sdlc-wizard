#!/usr/bin/env bash
# Configure an OpenCode backend by writing/merging opencode.json in the
# current (or --target-dir) repo.
#
# Privacy tiers (privacy-first, ordered):
#   private_local   ollama / lm_studio / llama_cpp / vllm
#   enterprise      azure_openai / aws_bedrock
#   hosted_oss      together / groq / openrouter
#   proprietary     anthropic / openai
#
# Usage:
#   configure-backend.sh --tier <tier> --provider <provider> --model <model>
#                        [--target-dir PATH] [--force] [--print-only]
#
# Behavior:
#   - Reads existing opencode.json if present, preserves unrelated keys
#   - Refuses to clobber an existing model pin unless --force
#   - --print-only emits the merged JSON to stdout WITHOUT writing the file
#   - Idempotent: re-running with the same args produces byte-identical output

set -euo pipefail

TIER=""
PROVIDER=""
MODEL=""
TARGET_DIR="$(pwd)"
FORCE=0
PRINT_ONLY=0

usage() {
  sed -n '2,15p' "$0"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --tier) shift; TIER="${1:-}" ;;
    --tier=*) TIER="${1#*=}" ;;
    --provider) shift; PROVIDER="${1:-}" ;;
    --provider=*) PROVIDER="${1#*=}" ;;
    --model) shift; MODEL="${1:-}" ;;
    --model=*) MODEL="${1#*=}" ;;
    --target-dir) shift; TARGET_DIR="${1:-}" ;;
    --target-dir=*) TARGET_DIR="${1#*=}" ;;
    --force) FORCE=1 ;;
    --print-only) PRINT_ONLY=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

[ -n "$TIER" ]     || { echo "--tier is required"     >&2; exit 2; }
[ -n "$PROVIDER" ] || { echo "--provider is required" >&2; exit 2; }
[ -n "$MODEL" ]    || { echo "--model is required"    >&2; exit 2; }
[ -d "$TARGET_DIR" ] || { echo "Target dir does not exist: $TARGET_DIR" >&2; exit 2; }

CONFIG_PATH="$TARGET_DIR/opencode.json"

# Build the provider-specific fragment as a JSON string. We keep this in a
# heredoc-fed node script so we don't have to escape JSON in bash, and so
# the merge logic stays canonical (sorted keys, 2-space indent, trailing \n).
node - "$TIER" "$PROVIDER" "$MODEL" "$CONFIG_PATH" "$FORCE" "$PRINT_ONLY" <<'NODE'
const fs = require("node:fs");
const [tier, providerArg, model, configPath, forceStr, printOnlyStr] = process.argv.slice(2);
const force = forceStr === "1";
const printOnly = printOnlyStr === "1";

// Canonical provider IDs. Detector emits user-friendly aliases; we accept both
// and emit the canonical OpenCode/models.dev ID in the written config so model
// resolution actually works.
const PROVIDER_ALIASES = {
  // enterprise
  azure: "azure",
  azure_openai: "azure",
  bedrock: "amazon-bedrock",
  aws_bedrock: "amazon-bedrock",
  amazon_bedrock: "amazon-bedrock",
  "amazon-bedrock": "amazon-bedrock",
  // hosted_oss
  together: "togetherai",
  togetherai: "togetherai",
  groq: "groq",
  openrouter: "openrouter",
  // private_local
  ollama: "ollama",
  lm_studio: "lmstudio",
  lmstudio: "lmstudio",
  llama_cpp: "llamacpp",
  llamacpp: "llamacpp",
  vllm: "vllm",
  // proprietary
  anthropic: "anthropic",
  openai: "openai",
};
const provider = PROVIDER_ALIASES[providerArg] || providerArg;

// Provider fragment templates. For CUSTOM providers (private_local + hosted_oss
// going through @ai-sdk/openai-compatible), include a `models` entry so OpenCode
// can resolve the pin — without it, `opencode run` reports
// ProviderModelNotFoundError because models.dev has no entry for the custom id.
// Built-in providers (azure, amazon-bedrock, anthropic, openai) do NOT need a
// `models` entry — their model registry is auto-resolved from models.dev.
function fragmentFor(tier, provider, model) {
  const t = `${tier}/${provider}`;
  switch (t) {
    case "private_local/ollama":
      return {
        model: `ollama/${model}`,
        provider: {
          ollama: {
            npm: "@ai-sdk/openai-compatible",
            options: { baseURL: "http://localhost:11434/v1" },
            models: { [model]: {} },
          },
        },
      };
    case "private_local/lmstudio":
      return {
        model: `lmstudio/${model}`,
        provider: {
          lmstudio: {
            npm: "@ai-sdk/openai-compatible",
            options: { baseURL: "http://127.0.0.1:1234/v1" },
            models: { [model]: {} },
          },
        },
      };
    case "private_local/llamacpp":
      return {
        model: `llamacpp/${model}`,
        provider: {
          llamacpp: {
            npm: "@ai-sdk/openai-compatible",
            options: { baseURL: "http://127.0.0.1:8080/v1" },
            models: { [model]: {} },
          },
        },
      };
    case "private_local/vllm":
      return {
        model: `vllm/${model}`,
        provider: {
          vllm: {
            npm: "@ai-sdk/openai-compatible",
            options: { baseURL: "http://127.0.0.1:8000/v1" },
            models: { [model]: {} },
          },
        },
      };
    case "enterprise/azure":
      return {
        model: `azure/${model}`,
        provider: {
          azure: {
            options: {
              apiKey: "{env:AZURE_API_KEY}",
              resourceName: "{env:AZURE_RESOURCE_NAME}",
            },
          },
        },
      };
    case "enterprise/amazon-bedrock":
      return {
        model: `amazon-bedrock/${model}`,
        provider: {
          "amazon-bedrock": {
            options: { region: "{env:AWS_REGION}" },
          },
        },
      };
    case "hosted_oss/togetherai":
      return {
        model: `togetherai/${model}`,
        provider: {
          togetherai: {
            npm: "@ai-sdk/openai-compatible",
            options: {
              apiKey: "{env:TOGETHER_API_KEY}",
              baseURL: "https://api.together.xyz/v1",
            },
            models: { [model]: {} },
          },
        },
      };
    case "hosted_oss/groq":
      return {
        model: `groq/${model}`,
        provider: {
          groq: {
            npm: "@ai-sdk/openai-compatible",
            options: {
              apiKey: "{env:GROQ_API_KEY}",
              baseURL: "https://api.groq.com/openai/v1",
            },
            models: { [model]: {} },
          },
        },
      };
    case "hosted_oss/openrouter":
      return {
        model: `openrouter/${model}`,
        provider: {
          openrouter: {
            npm: "@ai-sdk/openai-compatible",
            options: {
              apiKey: "{env:OPENROUTER_API_KEY}",
              baseURL: "https://openrouter.ai/api/v1",
            },
            models: { [model]: {} },
          },
        },
      };
    case "proprietary/anthropic":
      return {
        model: `anthropic/${model}`,
        provider: {
          anthropic: {
            options: { apiKey: "{env:ANTHROPIC_API_KEY}" },
          },
        },
      };
    case "proprietary/openai":
      return {
        model: `openai/${model}`,
        provider: {
          openai: {
            options: { apiKey: "{env:OPENAI_API_KEY}" },
          },
        },
      };
    default:
      throw new Error(`unsupported tier/provider: ${t}`);
  }
}

function isPlainObject(v) {
  return v && typeof v === "object" && !Array.isArray(v);
}

// Deep merge: for each key in `add`, if both sides are plain objects, recurse;
// otherwise take `add`'s value. Used to merge a freshly-built provider fragment
// over an existing provider block without dropping fields like `name`,
// `timeout`, or accumulated `models` entries.
function deepMerge(base, add) {
  if (!isPlainObject(base)) return add;
  if (!isPlainObject(add)) return add;
  const out = { ...base };
  for (const k of Object.keys(add)) {
    out[k] = isPlainObject(base[k]) && isPlainObject(add[k])
      ? deepMerge(base[k], add[k])
      : add[k];
  }
  return out;
}

// Load existing opencode.json if present
let existing = {};
if (fs.existsSync(configPath)) {
  try {
    existing = JSON.parse(fs.readFileSync(configPath, "utf8"));
  } catch (e) {
    process.stderr.write(`opencode.json exists but is invalid JSON: ${e.message}\n`);
    process.exit(3);
  }
}

// Build canonical merged config: deep-merge provider (preserves existing
// provider keys like `name`/`timeout`/`models`), replace `model` field.
const fragment = fragmentFor(tier, provider, model);
const merged = { ...existing, model: fragment.model };
merged.provider = deepMerge(existing.provider || {}, fragment.provider || {});

// Canonical key ordering for deterministic output (idempotency requirement).
// Top-level: $schema, model, provider, then everything else alphabetical.
function sortKeysCanonical(obj, topLevel = false) {
  if (Array.isArray(obj)) return obj.map((v) => sortKeysCanonical(v, false));
  if (obj && typeof obj === "object") {
    const keys = Object.keys(obj);
    let ordered;
    if (topLevel) {
      const preferred = ["$schema", "model", "provider"];
      const front = preferred.filter((k) => keys.includes(k));
      const rest = keys.filter((k) => !preferred.includes(k)).sort();
      ordered = [...front, ...rest];
    } else {
      ordered = keys.sort();
    }
    const out = {};
    for (const k of ordered) out[k] = sortKeysCanonical(obj[k], false);
    return out;
  }
  return obj;
}
const canonical = sortKeysCanonical(merged, true);
const out = JSON.stringify(canonical, null, 2) + "\n";

// Read current file content (if any) for idempotency check below
const existingFileContent = fs.existsSync(configPath)
  ? fs.readFileSync(configPath, "utf8")
  : "";

// No-clobber guard. Refuse to overwrite an existing model pin unless --force,
// EXCEPT when the proposed merged content is byte-identical to what's on disk:
// that's an idempotent re-run, which should succeed silently. Without this
// carve-out, a setup-wizard skill that calls configure-backend twice with the
// same args would error on the second call.
if (
  !force &&
  typeof existing.model === "string" &&
  existing.model.length > 0 &&
  existingFileContent !== out
) {
  process.stderr.write(
    `opencode.json already has model="${existing.model}". Re-run with --force to overwrite.\n`,
  );
  process.exit(4);
}

if (printOnly) {
  process.stdout.write(out);
} else if (existingFileContent === out) {
  // Idempotent no-op: file already matches canonical merged content. Don't
  // touch the filesystem (preserves mtime), exit 0.
  process.stderr.write(
    `${configPath} already up to date (no-op)\n  model=${canonical.model}\n  tier=${tier}/${provider}\n`,
  );
} else {
  fs.writeFileSync(configPath, out);
  process.stderr.write(
    `Wrote ${configPath}\n  model=${canonical.model}\n  tier=${tier}/${provider}\n`,
  );
}
NODE
