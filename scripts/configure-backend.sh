#!/usr/bin/env bash
# Configure an OpenCode backend by writing/merging opencode.json in the
# current (or --target-dir) repo.
#
# Privacy tiers (privacy-first, ordered):
#   private_local   ollama / lm_studio / llama_cpp / vllm / mlx
#   enterprise      azure_openai / aws_bedrock
#   hosted_oss      together / groq / openrouter / cerebras / deepseek / nvidia_nim
#   proprietary     anthropic / openai / google_aistudio
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
# v0.10.0 Mixed-Mode: optional reviewer model routing. When all three of
# REVIEWER_TIER/REVIEWER_PROVIDER/REVIEWER_MODEL are set, configure-backend
# writes `agent.review.model` (and the reviewer's provider block if it
# differs from the coder's) into the merged opencode.json.
REVIEWER_TIER=""
REVIEWER_PROVIDER=""
REVIEWER_MODEL=""

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
    --reviewer-tier) shift; REVIEWER_TIER="${1:-}" ;;
    --reviewer-tier=*) REVIEWER_TIER="${1#*=}" ;;
    --reviewer-provider) shift; REVIEWER_PROVIDER="${1:-}" ;;
    --reviewer-provider=*) REVIEWER_PROVIDER="${1#*=}" ;;
    --reviewer-model) shift; REVIEWER_MODEL="${1:-}" ;;
    --reviewer-model=*) REVIEWER_MODEL="${1#*=}" ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

[ -n "$TIER" ]     || { echo "--tier is required"     >&2; exit 2; }
[ -n "$PROVIDER" ] || { echo "--provider is required" >&2; exit 2; }
[ -n "$MODEL" ]    || { echo "--model is required"    >&2; exit 2; }
[ -d "$TARGET_DIR" ] || { echo "Target dir does not exist: $TARGET_DIR" >&2; exit 2; }

# Mixed-Mode validation: --reviewer-* flags are all-or-nothing. Partial
# reviewer spec would silently produce a single-mode config — fail loud.
RV_SET=0
[ -n "$REVIEWER_TIER" ] && RV_SET=$((RV_SET+1))
[ -n "$REVIEWER_PROVIDER" ] && RV_SET=$((RV_SET+1))
[ -n "$REVIEWER_MODEL" ] && RV_SET=$((RV_SET+1))
if [ "$RV_SET" -ne 0 ] && [ "$RV_SET" -ne 3 ]; then
  echo "--reviewer-tier / --reviewer-provider / --reviewer-model must all be set together (or none)" >&2
  exit 2
fi

CONFIG_PATH="$TARGET_DIR/opencode.json"

# Build the provider-specific fragment as a JSON string. We keep this in a
# heredoc-fed node script so we don't have to escape JSON in bash, and so
# the merge logic stays canonical (sorted keys, 2-space indent, trailing \n).
node - "$TIER" "$PROVIDER" "$MODEL" "$CONFIG_PATH" "$FORCE" "$PRINT_ONLY" \
     "$REVIEWER_TIER" "$REVIEWER_PROVIDER" "$REVIEWER_MODEL" <<'NODE'
const fs = require("node:fs");
const [
  tier, providerArg, model, configPath, forceStr, printOnlyStr,
  reviewerTier, reviewerProviderArg, reviewerModel,
] = process.argv.slice(2);
const force = forceStr === "1";
const printOnly = printOnlyStr === "1";
const mixedMode = Boolean(reviewerTier && reviewerProviderArg && reviewerModel);

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
  cerebras: "cerebras",
  deepseek: "deepseek",
  nvidia_nim: "nvidia",
  "nvidia-nim": "nvidia",
  nvidia: "nvidia",
  // private_local
  ollama: "ollama",
  lm_studio: "lmstudio",
  lmstudio: "lmstudio",
  llama_cpp: "llamacpp",
  llamacpp: "llamacpp",
  vllm: "vllm",
  mlx: "mlx",
  // proprietary
  anthropic: "anthropic",
  openai: "openai",
  google_aistudio: "google",
  google: "google",
  gemini: "google",
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
    case "private_local/mlx":
      // mlx_lm.server defaults to port 8080. Apple-Silicon-only.
      return {
        model: `mlx/${model}`,
        provider: {
          mlx: {
            npm: "@ai-sdk/openai-compatible",
            options: { baseURL: "http://127.0.0.1:8080/v1" },
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
    case "hosted_oss/cerebras":
      return {
        model: `cerebras/${model}`,
        provider: {
          cerebras: {
            npm: "@ai-sdk/openai-compatible",
            options: {
              apiKey: "{env:CEREBRAS_API_KEY}",
              baseURL: "https://api.cerebras.ai/v1",
            },
            models: { [model]: {} },
          },
        },
      };
    case "hosted_oss/deepseek":
      return {
        model: `deepseek/${model}`,
        provider: {
          deepseek: {
            npm: "@ai-sdk/openai-compatible",
            options: {
              apiKey: "{env:DEEPSEEK_API_KEY}",
              baseURL: "https://api.deepseek.com/v1",
            },
            models: { [model]: {} },
          },
        },
      };
    case "hosted_oss/nvidia":
      return {
        model: `nvidia/${model}`,
        provider: {
          nvidia: {
            npm: "@ai-sdk/openai-compatible",
            options: {
              apiKey: "{env:NVIDIA_API_KEY}",
              baseURL: "https://integrate.api.nvidia.com/v1",
            },
            models: { [model]: {} },
          },
        },
      };
    case "proprietary/google":
      // Google AI Studio (Gemini). Closed weights, but generous free tier
      // (1500 req/day on Flash). OpenCode talks to Google's OpenAI-compatible
      // endpoint at generativelanguage.googleapis.com.
      return {
        model: `google/${model}`,
        provider: {
          google: {
            npm: "@ai-sdk/openai-compatible",
            options: {
              apiKey: "{env:GOOGLE_API_KEY}",
              baseURL: "https://generativelanguage.googleapis.com/v1beta/openai",
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

// v0.10.0 Mixed-Mode: when --reviewer-* triplet is set, also merge the
// reviewer's provider block (skipped when reviewer = coder) and set
// agent.review.model to the reviewer's "<provider>/<model>" pin. Per the
// May-2026 community-patterns research, this maps to how 11/15 surveyed
// configs route review work to a separate model from build work.
if (mixedMode) {
  const reviewerProvider = PROVIDER_ALIASES[reviewerProviderArg] || reviewerProviderArg;
  const reviewerFragment = fragmentFor(reviewerTier, reviewerProvider, reviewerModel);
  // Deep-merge reviewer's provider block. If coder + reviewer share a
  // provider (e.g., both anthropic with different models), this collapses
  // to a single block — provider blocks key on canonical provider id.
  merged.provider = deepMerge(merged.provider, reviewerFragment.provider || {});
  // Inject agent.review.model. Preserve any user-set sibling fields
  // (temperature, tools, permission) by deep-merging at the agent.review
  // level rather than overwriting the whole object.
  merged.agent = deepMerge(existing.agent || {}, {
    review: { model: reviewerFragment.model },
  });
}

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
