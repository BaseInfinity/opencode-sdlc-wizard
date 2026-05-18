#!/usr/bin/env bash
# Configure an OpenCode backend by writing/merging opencode.json in the
# current (or --target-dir) repo.
#
# Privacy tiers (privacy-first, ordered):
#   private_local   ollama / lm_studio / llama_cpp / vllm / mlx
#   enterprise      azure_openai / aws_bedrock
#   hosted_oss      together / groq / openrouter / cerebras / deepseek / nvidia_nim
#   proprietary     anthropic / openai / google_aistudio / zai
#   managed         opencode (OpenCode Zen — vendor-routed PAYG over 40+ models)
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
# v0.10.2 Planner agent model routing. Same shape as v0.10.0 reviewer
# flags. Per-community usage: `plan` is the second-most-routed agent
# after `review` — typical split is plan=small/fast, build=mid,
# review=high. Writes `agent.plan.model` block + planner provider block.
PLANNER_TIER=""
PLANNER_PROVIDER=""
PLANNER_MODEL=""
# v0.10.4 small_model: top-level fast/cheap fallback distinct from
# agent.plan.model. Community signal: 35-40% of configs set this. Same
# triplet shape, writes the top-level `small_model` field plus the
# small-model provider block (deep-merged with coder/reviewer/planner).
SMALL_TIER=""
SMALL_PROVIDER=""
SMALL_MODEL=""
# v0.10.1 Per-agent permission sandboxing. Boolean flags inject canonical
# permission.write blocks for the two highest-signal agents from May-2026
# community-patterns research (9/15 configs use this): test-writer scoped
# to test/spec files only, docs scoped to .md only. Users wanting custom
# glob patterns edit opencode.json directly.
SANDBOX_TEST_WRITER=0
SANDBOX_DOCS=0
# v0.10.5 --sandbox-plan: plan-mode tool denial. Sets agent.plan.tools
# write/edit/patch all false so the planner can read + reason but not
# modify code. Distinct from v0.10.1 permission.write blocks — those
# are path-scoped allow/deny on writes; this is categorical tool disable.
SANDBOX_PLAN=0
# v0.11.1 per-agent temperatures. Community pattern (joelhooks + ppries):
# plan=0.1 (deterministic), build=0.3 (some creativity), review=0.1
# (deterministic). Empty string means "not set" → no temperature field
# emitted on that agent block.
CODER_TEMP=""
PLANNER_TEMP=""
REVIEWER_TEMP=""
SECURITY_TEMP=""
# v0.11.2 security agent. Same triplet shape as reviewer/planner;
# writes agent.security.model + security provider block. Plus the
# matching --sandbox-security flag for tools.{write,edit,patch}=false.
SECURITY_TIER=""
SECURITY_PROVIDER=""
SECURITY_MODEL=""
SANDBOX_SECURITY=0

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
    --planner-tier) shift; PLANNER_TIER="${1:-}" ;;
    --planner-tier=*) PLANNER_TIER="${1#*=}" ;;
    --planner-provider) shift; PLANNER_PROVIDER="${1:-}" ;;
    --planner-provider=*) PLANNER_PROVIDER="${1#*=}" ;;
    --planner-model) shift; PLANNER_MODEL="${1:-}" ;;
    --planner-model=*) PLANNER_MODEL="${1#*=}" ;;
    --small-tier) shift; SMALL_TIER="${1:-}" ;;
    --small-tier=*) SMALL_TIER="${1#*=}" ;;
    --small-provider) shift; SMALL_PROVIDER="${1:-}" ;;
    --small-provider=*) SMALL_PROVIDER="${1#*=}" ;;
    --small-model) shift; SMALL_MODEL="${1:-}" ;;
    --small-model=*) SMALL_MODEL="${1#*=}" ;;
    --sandbox-test-writer) SANDBOX_TEST_WRITER=1 ;;
    --sandbox-docs) SANDBOX_DOCS=1 ;;
    --sandbox-plan) SANDBOX_PLAN=1 ;;
    --coder-temp) shift; CODER_TEMP="${1:-}" ;;
    --coder-temp=*) CODER_TEMP="${1#*=}" ;;
    --planner-temp) shift; PLANNER_TEMP="${1:-}" ;;
    --planner-temp=*) PLANNER_TEMP="${1#*=}" ;;
    --reviewer-temp) shift; REVIEWER_TEMP="${1:-}" ;;
    --reviewer-temp=*) REVIEWER_TEMP="${1#*=}" ;;
    --security-temp) shift; SECURITY_TEMP="${1:-}" ;;
    --security-temp=*) SECURITY_TEMP="${1#*=}" ;;
    --security-tier) shift; SECURITY_TIER="${1:-}" ;;
    --security-tier=*) SECURITY_TIER="${1#*=}" ;;
    --security-provider) shift; SECURITY_PROVIDER="${1:-}" ;;
    --security-provider=*) SECURITY_PROVIDER="${1#*=}" ;;
    --security-model) shift; SECURITY_MODEL="${1:-}" ;;
    --security-model=*) SECURITY_MODEL="${1#*=}" ;;
    --sandbox-security) SANDBOX_SECURITY=1 ;;
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

# v0.10.2 planner validation: same all-or-nothing rule.
PL_SET=0
[ -n "$PLANNER_TIER" ] && PL_SET=$((PL_SET+1))
[ -n "$PLANNER_PROVIDER" ] && PL_SET=$((PL_SET+1))
[ -n "$PLANNER_MODEL" ] && PL_SET=$((PL_SET+1))
if [ "$PL_SET" -ne 0 ] && [ "$PL_SET" -ne 3 ]; then
  echo "--planner-tier / --planner-provider / --planner-model must all be set together (or none)" >&2
  exit 2
fi

# v0.11.2 security validation: same all-or-nothing rule.
SC_SET=0
[ -n "$SECURITY_TIER" ] && SC_SET=$((SC_SET+1))
[ -n "$SECURITY_PROVIDER" ] && SC_SET=$((SC_SET+1))
[ -n "$SECURITY_MODEL" ] && SC_SET=$((SC_SET+1))
if [ "$SC_SET" -ne 0 ] && [ "$SC_SET" -ne 3 ]; then
  echo "--security-tier / --security-provider / --security-model must all be set together (or none)" >&2
  exit 2
fi

# v0.10.4 small-model validation.
SM_SET=0
[ -n "$SMALL_TIER" ] && SM_SET=$((SM_SET+1))
[ -n "$SMALL_PROVIDER" ] && SM_SET=$((SM_SET+1))
[ -n "$SMALL_MODEL" ] && SM_SET=$((SM_SET+1))
if [ "$SM_SET" -ne 0 ] && [ "$SM_SET" -ne 3 ]; then
  echo "--small-tier / --small-provider / --small-model must all be set together (or none)" >&2
  exit 2
fi

CONFIG_PATH="$TARGET_DIR/opencode.json"

# Build the provider-specific fragment as a JSON string. We keep this in a
# heredoc-fed node script so we don't have to escape JSON in bash, and so
# the merge logic stays canonical (sorted keys, 2-space indent, trailing \n).
node - "$TIER" "$PROVIDER" "$MODEL" "$CONFIG_PATH" "$FORCE" "$PRINT_ONLY" \
     "$REVIEWER_TIER" "$REVIEWER_PROVIDER" "$REVIEWER_MODEL" \
     "$SANDBOX_TEST_WRITER" "$SANDBOX_DOCS" \
     "$PLANNER_TIER" "$PLANNER_PROVIDER" "$PLANNER_MODEL" \
     "$SMALL_TIER" "$SMALL_PROVIDER" "$SMALL_MODEL" \
     "$SANDBOX_PLAN" \
     "$CODER_TEMP" "$PLANNER_TEMP" "$REVIEWER_TEMP" \
     "$SECURITY_TIER" "$SECURITY_PROVIDER" "$SECURITY_MODEL" \
     "$SECURITY_TEMP" "$SANDBOX_SECURITY" <<'NODE'
const fs = require("node:fs");
const [
  tier, providerArg, model, configPath, forceStr, printOnlyStr,
  reviewerTier, reviewerProviderArg, reviewerModel,
  sandboxTestWriterStr, sandboxDocsStr,
  plannerTier, plannerProviderArg, plannerModel,
  smallTier, smallProviderArg, smallModel,
  sandboxPlanStr,
  coderTempStr, plannerTempStr, reviewerTempStr,
  securityTier, securityProviderArg, securityModel,
  securityTempStr, sandboxSecurityStr,
] = process.argv.slice(2);
const force = forceStr === "1";
const printOnly = printOnlyStr === "1";
const mixedMode = Boolean(reviewerTier && reviewerProviderArg && reviewerModel);
const sandboxTestWriter = sandboxTestWriterStr === "1";
const sandboxDocs = sandboxDocsStr === "1";
const plannerMode = Boolean(plannerTier && plannerProviderArg && plannerModel);
const smallMode = Boolean(smallTier && smallProviderArg && smallModel);
const sandboxPlan = sandboxPlanStr === "1";
const securityMode = Boolean(securityTier && securityProviderArg && securityModel);
const sandboxSecurity = sandboxSecurityStr === "1";
// Parse temperatures only if non-empty; empty string means "not set"
// (no temperature field emitted). Numbers preserve as numbers in JSON.
function parseTemp(s) { return s === "" ? null : Number(s); }
const coderTemp = parseTemp(coderTempStr);
const plannerTemp = parseTemp(plannerTempStr);
const reviewerTemp = parseTemp(reviewerTempStr);
const securityTemp = parseTemp(securityTempStr);

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
  // v0.11.0: Z.AI GLM Coding Plan (proprietary, GLM closed weights).
  zai: "zai",
  "z.ai": "zai",
  z_ai: "zai",
  glm: "zai",
  // v0.12.0: OpenCode Zen — managed tier, vendor-routed PAYG over 40+
  // models. Canonical provider id in opencode.json is "opencode" per
  // Zen's docs (model pin format: "opencode/<model>").
  opencode: "opencode",
  opencode_zen: "opencode",
  "opencode-zen": "opencode",
  zen: "opencode",
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
    case "proprietary/zai":
      // Z.AI GLM Coding Plan. Closed weights, OpenAI-compatible API at
      // https://api.z.ai/api/paas/v4/. May-2026 community signal: most-cited
      // post-Anthropic-OAuth-ban migration target ($10/$30/$80 quarterly
      // pricing for the Coding Plan; PAYG also available).
      return {
        model: `zai/${model}`,
        provider: {
          zai: {
            npm: "@ai-sdk/openai-compatible",
            options: {
              apiKey: "{env:ZAI_API_KEY}",
              baseURL: "https://api.z.ai/api/paas/v4",
            },
            models: { [model]: {} },
          },
        },
      };
    case "managed/opencode":
      // OpenCode Zen — vendor-managed routing over 40+ models including
      // a free tier (Big Pickle, DeepSeek V4 Flash Free, MiniMax M2.5
      // Free, Nemotron 3 Super Free). PAYG, $5 auto-reload trigger.
      // Provider id is "opencode" per Zen's own docs (model pin format
      // "opencode/<model>"). OpenAI-compatible endpoint at
      // https://opencode.ai/zen/v1.
      return {
        model: `opencode/${model}`,
        provider: {
          opencode: {
            npm: "@ai-sdk/openai-compatible",
            options: {
              apiKey: "{env:OPENCODE_ZEN_API_KEY}",
              baseURL: "https://opencode.ai/zen/v1",
            },
            models: { [model]: {} },
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

// v0.10.2 Planner mode: identical shape to reviewer, agent.plan.model
// instead of agent.review.model. Composes with reviewer (both blocks
// land in agent), uses same PROVIDER_ALIASES + fragmentFor, merges
// provider blocks into the same provider map.
if (plannerMode) {
  const plannerProvider = PROVIDER_ALIASES[plannerProviderArg] || plannerProviderArg;
  const plannerFragment = fragmentFor(plannerTier, plannerProvider, plannerModel);
  merged.provider = deepMerge(merged.provider, plannerFragment.provider || {});
  merged.agent = deepMerge(merged.agent || existing.agent || {}, {
    plan: { model: plannerFragment.model },
  });
}

// v0.11.2 Security mode: identical shape to planner. Writes
// agent.security.model + security provider block. Joelhooks-pattern
// security agent typically pairs with --sandbox-security below.
if (securityMode) {
  const securityProvider = PROVIDER_ALIASES[securityProviderArg] || securityProviderArg;
  const securityFragment = fragmentFor(securityTier, securityProvider, securityModel);
  merged.provider = deepMerge(merged.provider, securityFragment.provider || {});
  merged.agent = deepMerge(merged.agent || existing.agent || {}, {
    security: { model: securityFragment.model },
  });
}

// v0.10.4 small_model: top-level field (not nested under agent). Distinct
// from agent.plan.model — small_model is OpenCode's cross-cutting hint
// for "use this when the call is cheap" (title generation, summary
// blurbs, etc.). 35-40% of community configs set this.
if (smallMode) {
  const smallProvider = PROVIDER_ALIASES[smallProviderArg] || smallProviderArg;
  const smallFragment = fragmentFor(smallTier, smallProvider, smallModel);
  merged.provider = deepMerge(merged.provider, smallFragment.provider || {});
  merged.small_model = smallFragment.model;
}

// v0.10.1 Per-agent permission sandboxing. Each flag injects the canonical
// permission.write pattern for that agent — deep-merged so it composes
// with Mixed-Mode (--reviewer-*) and any user-set sibling fields. Patterns
// derived from the most-cited community examples (joelhooks, ppries gists).
// v0.10.5: --sandbox-plan adds agent.plan.tools = {write,edit,patch: false}
// — categorical tool denial, distinct shape from the path-scoped
// permission.write blocks above. Composes with v0.10.2 planner model
// (agent.plan ends up with both .model AND .tools when both flags set).
if (sandboxTestWriter || sandboxDocs || sandboxPlan || sandboxSecurity) {
  const sandboxAdditions = {};
  if (sandboxTestWriter) {
    sandboxAdditions["test-writer"] = {
      permission: {
        write: {
          "**/*.test.*": "allow",
          "**/*.spec.*": "allow",
          "*": "deny",
        },
      },
    };
  }
  if (sandboxDocs) {
    sandboxAdditions["docs"] = {
      permission: {
        write: {
          "**/*.md": "allow",
          "*": "deny",
        },
      },
    };
  }
  if (sandboxPlan) {
    sandboxAdditions["plan"] = {
      tools: { write: false, edit: false, patch: false },
    };
  }
  // v0.11.2: security agent denies the same tools as plan — read +
  // reason, never write. Joelhooks-pattern; matches the canonical
  // "security review can't accidentally apply a patch" guarantee.
  if (sandboxSecurity) {
    sandboxAdditions["security"] = {
      tools: { write: false, edit: false, patch: false },
    };
  }
  merged.agent = deepMerge(merged.agent || existing.agent || {}, sandboxAdditions);
}

// v0.11.1 per-agent temperatures. Each non-null value sets the
// agent.<name>.temperature field; deep-merges with any existing model /
// tools / permission siblings on that agent. --coder-temp targets the
// `build` agent (OpenCode's default agent name for code generation).
if (coderTemp !== null || plannerTemp !== null || reviewerTemp !== null || securityTemp !== null) {
  const tempAdditions = {};
  if (coderTemp !== null) tempAdditions["build"] = { temperature: coderTemp };
  if (plannerTemp !== null) tempAdditions["plan"] = { temperature: plannerTemp };
  if (reviewerTemp !== null) tempAdditions["review"] = { temperature: reviewerTemp };
  if (securityTemp !== null) tempAdditions["security"] = { temperature: securityTemp };
  merged.agent = deepMerge(merged.agent || existing.agent || {}, tempAdditions);
}

// Canonical key ordering for deterministic output (idempotency requirement).
// Top-level: $schema, model, provider, then everything else alphabetical.
function sortKeysCanonical(obj, topLevel = false) {
  if (Array.isArray(obj)) return obj.map((v) => sortKeysCanonical(v, false));
  if (obj && typeof obj === "object") {
    const keys = Object.keys(obj);
    let ordered;
    if (topLevel) {
      // v0.10.4: small_model lives right after `model` per the joelhooks
      // and ppries community configs we surveyed — keeps the two top-level
      // pins visually adjacent.
      const preferred = ["$schema", "model", "small_model", "provider"];
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
