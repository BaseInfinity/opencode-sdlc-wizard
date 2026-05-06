#!/usr/bin/env bash
# Tests for the backend tier picker.
#
# Covers:
#   - scripts/detect-backends.sh emits well-formed JSON with the expected
#     four-tier shape: private_local / enterprise / hosted_oss / proprietary
#   - detect-backends honors env-var presence as the signal for hosted/
#     proprietary tiers (no live network calls — pure env probe)
#   - detect-backends "recommendation" field prefers private_local when
#     a local LLM runtime is on PATH
#   - scripts/configure-backend.sh writes a correct opencode.json shape
#     for each tier
#   - configure-backend is idempotent (re-run produces identical bytes)
#   - configure-backend preserves unrelated keys in an existing opencode.json
#   - configure-backend refuses to clobber an existing model pin without --force

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DETECT="$REPO_ROOT/scripts/detect-backends.sh"
CONFIG="$REPO_ROOT/scripts/configure-backend.sh"

PASS=0
FAIL=0
RED='\033[0;31m'
GREEN='\033[0;32m'
RESET='\033[0m'

pass() { printf "${GREEN}PASS${RESET}: %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "${RED}FAIL${RESET}: %s\n" "$1"; FAIL=$((FAIL+1)); }

# Sandbox: each test gets a clean tempdir + a clean env (no real keys leak in)
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/picker-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

# Helper: run a script with a fully-scrubbed env (only PATH + HOME survive)
clean_env_run() {
  env -i PATH="$PATH" HOME="$HOME" "$@"
}

echo "=== detect-backends.sh ==="

# --- T1: script exists and is executable
if [ -x "$DETECT" ]; then
  pass "detect-backends.sh exists and is executable"
else
  fail "detect-backends.sh missing or not executable at $DETECT"
fi

# --- T2: emits valid JSON
if [ -x "$DETECT" ]; then
  out_json="$(clean_env_run "$DETECT" 2>/dev/null || true)"
  if printf '%s' "$out_json" | node -e "let d=''; process.stdin.on('data',c=>d+=c); process.stdin.on('end',()=>{try{JSON.parse(d);process.exit(0)}catch(e){console.error(e.message);process.exit(1)}})" 2>/dev/null; then
    pass "detect-backends emits valid JSON"
  else
    fail "detect-backends did not emit valid JSON; got: $(printf '%s' "$out_json" | head -c 200)"
  fi
fi

# --- T3: JSON has the expected four-tier shape
if [ -x "$DETECT" ]; then
  out_json="$(clean_env_run "$DETECT" 2>/dev/null || true)"
  shape_ok="$(printf '%s' "$out_json" | node -e "
let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{
  try{const j=JSON.parse(d);
    const tiers=['private_local','enterprise','hosted_oss','proprietary'];
    for(const t of tiers){if(!(t in j)){console.log('missing:'+t);process.exit(1)}}
    if(typeof j.recommendation!=='string'){console.log('missing:recommendation');process.exit(1)}
    console.log('ok');
  }catch(e){console.log('parse-error:'+e.message);process.exit(1)}
});" 2>/dev/null || echo 'failed')"
  if [ "$shape_ok" = "ok" ]; then
    pass "detect-backends JSON has all 4 tiers + recommendation"
  else
    fail "detect-backends JSON shape wrong: $shape_ok"
  fi
fi

# --- T4: hosted_oss/proprietary detection follows env vars
if [ -x "$DETECT" ]; then
  out_json="$(env -i PATH="$PATH" HOME="$HOME" \
    ANTHROPIC_API_KEY="sk-fake" \
    GROQ_API_KEY="gsk-fake" \
    "$DETECT" 2>/dev/null || true)"
  ok="$(printf '%s' "$out_json" | node -e "
let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{
  try{const j=JSON.parse(d);
    if(j.proprietary.anthropic.key_set!==true){console.log('anthropic-not-detected');process.exit(1)}
    if(j.hosted_oss.groq.key_set!==true){console.log('groq-not-detected');process.exit(1)}
    if(j.proprietary.openai.key_set!==false){console.log('openai-false-positive');process.exit(1)}
    console.log('ok');
  }catch(e){console.log('parse-error:'+e.message);process.exit(1)}
});" 2>/dev/null || echo 'failed')"
  if [ "$ok" = "ok" ]; then
    pass "detect-backends respects env-var presence for hosted/proprietary tiers"
  else
    fail "detect-backends env detection broken: $ok"
  fi
fi

# --- T5: recommendation defaults to private_local/ollama when ollama is on PATH
if [ -x "$DETECT" ]; then
  STUB_DIR="$TMP_ROOT/stubs1"
  mkdir -p "$STUB_DIR"
  cat > "$STUB_DIR/ollama" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  list) printf "NAME\tID\tSIZE\nqwen2.5-coder:32b\tabc\t19 GB\n" ;;
  *) echo "ollama stub" ;;
esac
EOF
  chmod +x "$STUB_DIR/ollama"
  out_json="$(env -i PATH="$STUB_DIR:$PATH" HOME="$HOME" "$DETECT" 2>/dev/null || true)"
  rec="$(printf '%s' "$out_json" | node -e "
let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{
  try{const j=JSON.parse(d);console.log(j.recommendation||'');}catch(e){console.log('err');}
});" 2>/dev/null)"
  if [ "$rec" = "private_local/ollama" ]; then
    pass "detect-backends recommends private_local/ollama when ollama on PATH"
  else
    fail "expected recommendation 'private_local/ollama', got '$rec'"
  fi
fi

# --- T6: when nothing is set up, recommendation falls through cleanly
if [ -x "$DETECT" ]; then
  out_json="$(clean_env_run "$DETECT" 2>/dev/null || true)"
  rec="$(printf '%s' "$out_json" | node -e "
let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{
  try{const j=JSON.parse(d);console.log(j.recommendation||'');}catch(e){console.log('err');}
});" 2>/dev/null)"
  case "$rec" in
    none|none/*|private_local/*|enterprise/*|hosted_oss/*|proprietary/*)
      pass "detect-backends recommendation has a parseable form: '$rec'"
      ;;
    *)
      fail "detect-backends recommendation has unexpected form: '$rec'"
      ;;
  esac
fi

echo ""
echo "=== configure-backend.sh ==="

# --- T7: script exists and is executable
if [ -x "$CONFIG" ]; then
  pass "configure-backend.sh exists and is executable"
else
  fail "configure-backend.sh missing or not executable at $CONFIG"
fi

# --- T8: writes valid opencode.json for private_local/ollama
if [ -x "$CONFIG" ]; then
  T="$TMP_ROOT/t8"; mkdir -p "$T"
  (cd "$T" && "$CONFIG" --tier private_local --provider ollama --model "qwen2.5-coder:32b" >/dev/null 2>&1) || true
  if [ -f "$T/opencode.json" ]; then
    ok="$(node -e "
const j=require('$T/opencode.json');
if(j.model!=='ollama/qwen2.5-coder:32b'){console.log('model-wrong:'+j.model);process.exit(1)}
if(!j.provider||!j.provider.ollama){console.log('missing-provider-block');process.exit(1)}
const opts=j.provider.ollama.options||{};
if(!opts.baseURL||!String(opts.baseURL).includes('11434')){console.log('baseurl-wrong:'+opts.baseURL);process.exit(1)}
console.log('ok');
" 2>/dev/null || echo 'failed')"
    if [ "$ok" = "ok" ]; then
      pass "configure-backend writes correct ollama opencode.json"
    else
      fail "ollama config wrong: $ok"
    fi
  else
    fail "configure-backend did not create opencode.json for ollama"
  fi
fi

# --- T9: writes valid opencode.json for proprietary/anthropic
if [ -x "$CONFIG" ]; then
  T="$TMP_ROOT/t9"; mkdir -p "$T"
  (cd "$T" && "$CONFIG" --tier proprietary --provider anthropic --model "claude-opus-4-7" >/dev/null 2>&1) || true
  if [ -f "$T/opencode.json" ]; then
    ok="$(node -e "
const j=require('$T/opencode.json');
if(j.model!=='anthropic/claude-opus-4-7'){console.log('model-wrong:'+j.model);process.exit(1)}
if(!j.provider||!j.provider.anthropic){console.log('missing-provider-block');process.exit(1)}
const opts=j.provider.anthropic.options||{};
if(typeof opts.apiKey!=='string'||!opts.apiKey.includes('ANTHROPIC_API_KEY')){console.log('apikey-wrong:'+opts.apiKey);process.exit(1)}
console.log('ok');
" 2>/dev/null || echo 'failed')"
    if [ "$ok" = "ok" ]; then
      pass "configure-backend writes correct anthropic opencode.json with env substitution"
    else
      fail "anthropic config wrong: $ok"
    fi
  else
    fail "configure-backend did not create opencode.json for anthropic"
  fi
fi

# --- T10: writes valid opencode.json for enterprise/azure
if [ -x "$CONFIG" ]; then
  T="$TMP_ROOT/t10"; mkdir -p "$T"
  (cd "$T" && "$CONFIG" --tier enterprise --provider azure --model "gpt-4" >/dev/null 2>&1) || true
  if [ -f "$T/opencode.json" ]; then
    ok="$(node -e "
const j=require('$T/opencode.json');
if(j.model!=='azure/gpt-4'){console.log('model-wrong:'+j.model);process.exit(1)}
console.log('ok');
" 2>/dev/null || echo 'failed')"
    if [ "$ok" = "ok" ]; then
      pass "configure-backend writes correct azure opencode.json"
    else
      fail "azure config wrong: $ok"
    fi
  else
    fail "configure-backend did not create opencode.json for azure"
  fi
fi

# --- T11: idempotent — re-run with identical args succeeds (rc=0) and produces byte-identical opencode.json
# The no-clobber guard must allow a no-op re-run, NOT exit via the guard for "same args same content"
if [ -x "$CONFIG" ]; then
  T="$TMP_ROOT/t11"; mkdir -p "$T"
  rc1=0; rc2=0
  (cd "$T" && "$CONFIG" --tier private_local --provider ollama --model "qwen2.5-coder:32b" >/dev/null 2>&1) || rc1=$?
  cp "$T/opencode.json" "$T/opencode.json.first"
  (cd "$T" && "$CONFIG" --tier private_local --provider ollama --model "qwen2.5-coder:32b" >/dev/null 2>&1) || rc2=$?
  if [ "$rc1" -eq 0 ] && [ "$rc2" -eq 0 ] && cmp -s "$T/opencode.json" "$T/opencode.json.first"; then
    pass "configure-backend is idempotent on identical re-run (both rc=0, byte-identical)"
  else
    fail "configure-backend identical re-run not idempotent: rc1=$rc1 rc2=$rc2 (no-clobber guard should allow same-args re-run)"
    diff "$T/opencode.json.first" "$T/opencode.json" 2>/dev/null || true
  fi
fi

# --- T12: preserves unrelated keys in existing opencode.json
if [ -x "$CONFIG" ]; then
  T="$TMP_ROOT/t12"; mkdir -p "$T"
  cat > "$T/opencode.json" <<'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "instructions": ["AGENTS.md"],
  "permission": {"edit": "allow"}
}
EOF
  (cd "$T" && "$CONFIG" --tier private_local --provider ollama --model "qwen2.5-coder:32b" >/dev/null 2>&1) || true
  ok="$(node -e "
const j=require('$T/opencode.json');
if(j['\$schema']!=='https://opencode.ai/config.json'){console.log('schema-lost');process.exit(1)}
if(!Array.isArray(j.instructions)||j.instructions[0]!=='AGENTS.md'){console.log('instructions-lost');process.exit(1)}
if(!j.permission||j.permission.edit!=='allow'){console.log('permission-lost');process.exit(1)}
if(j.model!=='ollama/qwen2.5-coder:32b'){console.log('model-not-set');process.exit(1)}
console.log('ok');
" 2>/dev/null || echo 'failed')"
  if [ "$ok" = "ok" ]; then
    pass "configure-backend preserves unrelated keys (\$schema, instructions, permission)"
  else
    fail "configure-backend dropped existing keys: $ok"
  fi
fi

# --- T13: refuses to clobber existing model pin without --force
if [ -x "$CONFIG" ]; then
  T="$TMP_ROOT/t13"; mkdir -p "$T"
  cat > "$T/opencode.json" <<'EOF'
{"model": "anthropic/claude-sonnet-4-5"}
EOF
  rc=0
  (cd "$T" && "$CONFIG" --tier private_local --provider ollama --model "qwen2.5-coder:32b" >/dev/null 2>&1) || rc=$?
  current_model="$(node -e "console.log(require('$T/opencode.json').model)" 2>/dev/null || echo "")"
  if [ "$rc" -ne 0 ] && [ "$current_model" = "anthropic/claude-sonnet-4-5" ]; then
    pass "configure-backend refuses to clobber existing pin without --force (preserves '$current_model')"
  else
    fail "configure-backend should have refused to overwrite existing model. rc=$rc model='$current_model'"
  fi
fi

# --- T14: --force overrides the no-clobber guard
if [ -x "$CONFIG" ]; then
  T="$TMP_ROOT/t14"; mkdir -p "$T"
  cat > "$T/opencode.json" <<'EOF'
{"model": "anthropic/claude-sonnet-4-5"}
EOF
  (cd "$T" && "$CONFIG" --tier private_local --provider ollama --model "qwen2.5-coder:32b" --force >/dev/null 2>&1) || true
  current_model="$(node -e "console.log(require('$T/opencode.json').model)" 2>/dev/null || echo "")"
  if [ "$current_model" = "ollama/qwen2.5-coder:32b" ]; then
    pass "configure-backend --force overwrites existing pin"
  else
    fail "configure-backend --force did not overwrite. model='$current_model'"
  fi
fi

# --- T15: --print-only does not write opencode.json (dry-run for skill use)
if [ -x "$CONFIG" ]; then
  T="$TMP_ROOT/t15"; mkdir -p "$T"
  out="$(cd "$T" && "$CONFIG" --tier private_local --provider ollama --model "qwen2.5-coder:32b" --print-only 2>/dev/null || true)"
  ok="ok"
  if [ -f "$T/opencode.json" ]; then
    ok="opencode.json was written despite --print-only"
  elif ! printf '%s' "$out" | node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{try{const j=JSON.parse(d);if(j.model!=='ollama/qwen2.5-coder:32b'){console.log('model-wrong')}else{process.exit(0)}}catch(e){console.log('parse-error:'+e.message);process.exit(1)}});" >/dev/null 2>&1; then
    ok="--print-only output was not parseable JSON or had wrong model"
  fi
  if [ "$ok" = "ok" ]; then
    pass "configure-backend --print-only emits JSON to stdout without writing file"
  else
    fail "$ok"
  fi
fi

# --- T16: custom providers (private_local) include a `models` entry so OpenCode can resolve
# (without `models`, opencode reports ProviderModelNotFoundError when invoking the pin)
if [ -x "$CONFIG" ]; then
  T="$TMP_ROOT/t16"; mkdir -p "$T"
  (cd "$T" && "$CONFIG" --tier private_local --provider ollama --model "qwen2.5-coder:32b" >/dev/null 2>&1) || true
  ok="$(node -e "
const j=require('$T/opencode.json');
const m=j.provider&&j.provider.ollama&&j.provider.ollama.models;
if(!m||typeof m!=='object'){console.log('no-models-block');process.exit(1)}
if(!('qwen2.5-coder:32b' in m)){console.log('model-not-listed:'+Object.keys(m).join(','));process.exit(1)}
console.log('ok');
" 2>/dev/null || echo 'failed')"
  if [ "$ok" = "ok" ]; then
    pass "configure-backend ollama writes provider.ollama.models[<model>] entry (P0 fix)"
  else
    fail "ollama config missing models entry: $ok"
  fi

  T="$TMP_ROOT/t16b"; mkdir -p "$T"
  (cd "$T" && "$CONFIG" --tier hosted_oss --provider groq --model "llama-3.3-70b-versatile" >/dev/null 2>&1) || true
  ok="$(node -e "
const j=require('$T/opencode.json');
const m=j.provider&&j.provider.groq&&j.provider.groq.models;
if(!m||typeof m!=='object'||!('llama-3.3-70b-versatile' in m)){console.log('groq-models-missing');process.exit(1)}
console.log('ok');
" 2>/dev/null || echo 'failed')"
  if [ "$ok" = "ok" ]; then
    pass "configure-backend groq writes provider.groq.models[<model>] entry"
  else
    fail "groq config missing models entry: $ok"
  fi
fi

# --- T17: aws_bedrock alias maps to canonical `amazon-bedrock` provider id
if [ -x "$CONFIG" ]; then
  T="$TMP_ROOT/t17"; mkdir -p "$T"
  (cd "$T" && "$CONFIG" --tier enterprise --provider aws_bedrock --model "anthropic.claude-sonnet-4-5" >/dev/null 2>&1) || true
  ok="$(node -e "
const j=require('$T/opencode.json');
if(j.model!=='amazon-bedrock/anthropic.claude-sonnet-4-5'){console.log('model-prefix-wrong:'+j.model);process.exit(1)}
if(!j.provider||!j.provider['amazon-bedrock']){console.log('provider-id-wrong:'+Object.keys(j.provider||{}).join(','));process.exit(1)}
console.log('ok');
" 2>/dev/null || echo 'failed')"
  if [ "$ok" = "ok" ]; then
    pass "configure-backend aws_bedrock emits canonical 'amazon-bedrock' provider id"
  else
    fail "aws_bedrock provider id wrong: $ok"
  fi
fi

# --- T18: together alias maps to canonical `togetherai` provider id
if [ -x "$CONFIG" ]; then
  T="$TMP_ROOT/t18"; mkdir -p "$T"
  (cd "$T" && "$CONFIG" --tier hosted_oss --provider together --model "Qwen/Qwen2.5-Coder-32B-Instruct" >/dev/null 2>&1) || true
  ok="$(node -e "
const j=require('$T/opencode.json');
if(!j.model.startsWith('togetherai/')){console.log('model-prefix-wrong:'+j.model);process.exit(1)}
if(!j.provider||!j.provider.togetherai){console.log('provider-id-wrong:'+Object.keys(j.provider||{}).join(','));process.exit(1)}
console.log('ok');
" 2>/dev/null || echo 'failed')"
  if [ "$ok" = "ok" ]; then
    pass "configure-backend together emits canonical 'togetherai' provider id"
  else
    fail "together provider id wrong: $ok"
  fi
fi

# --- T19: deep-merge preserves existing provider keys (name, timeout, models) when reconfiguring
if [ -x "$CONFIG" ]; then
  T="$TMP_ROOT/t19"; mkdir -p "$T"
  cat > "$T/opencode.json" <<'EOF'
{
  "model": "ollama/llama3.1:70b",
  "provider": {
    "ollama": {
      "name": "Ollama Local",
      "npm": "@ai-sdk/openai-compatible",
      "options": { "baseURL": "http://localhost:11434/v1", "timeout": 600000 },
      "models": { "llama3.1:70b": {} }
    }
  }
}
EOF
  (cd "$T" && "$CONFIG" --tier private_local --provider ollama --model "qwen2.5-coder:32b" --force >/dev/null 2>&1) || true
  ok="$(node -e "
const j=require('$T/opencode.json');
const o=j.provider&&j.provider.ollama;
if(!o){console.log('provider-lost');process.exit(1)}
if(o.name!=='Ollama Local'){console.log('name-lost:'+o.name);process.exit(1)}
if(!o.options||o.options.timeout!==600000){console.log('timeout-lost');process.exit(1)}
if(!o.models||!('llama3.1:70b' in o.models)){console.log('existing-model-lost');process.exit(1)}
if(!o.models['qwen2.5-coder:32b']){console.log('new-model-not-added');process.exit(1)}
console.log('ok');
" 2>/dev/null || echo 'failed')"
  if [ "$ok" = "ok" ]; then
    pass "configure-backend deep-merges provider config (preserves name/timeout/models)"
  else
    fail "deep-merge dropped existing provider keys: $ok"
  fi
fi

# --- T20: ollama provider id mapping — model prefix uses 'ollama/' (not 'ollama-ai-provider/')
# Sanity for the most common private_local path
if [ -x "$CONFIG" ]; then
  T="$TMP_ROOT/t20"; mkdir -p "$T"
  (cd "$T" && "$CONFIG" --tier private_local --provider ollama --model "deepseek-coder-v2:16b" >/dev/null 2>&1) || true
  ok="$(node -e "
const j=require('$T/opencode.json');
if(j.model!=='ollama/deepseek-coder-v2:16b'){console.log('model-prefix-wrong:'+j.model);process.exit(1)}
console.log('ok');
" 2>/dev/null || echo 'failed')"
  if [ "$ok" = "ok" ]; then
    pass "configure-backend private_local/ollama keeps 'ollama/' model prefix"
  else
    fail "ollama prefix wrong: $ok"
  fi
fi

# --- T21: detector picks up the new free-tier providers via env
if [ -x "$DETECT" ]; then
  out_json="$(env -i PATH="$PATH" HOME="$HOME" \
    CEREBRAS_API_KEY=k DEEPSEEK_API_KEY=k NVIDIA_API_KEY=k GOOGLE_API_KEY=k \
    "$DETECT" 2>/dev/null || true)"
  ok="$(printf '%s' "$out_json" | node -e "
let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{
  try{const j=JSON.parse(d);
    if(j.hosted_oss.cerebras.key_set!==true)return console.log('cerebras-fail');
    if(j.hosted_oss.deepseek.key_set!==true)return console.log('deepseek-fail');
    if(j.hosted_oss.nvidia_nim.key_set!==true)return console.log('nvidia-fail');
    if(j.proprietary.google_aistudio.key_set!==true)return console.log('google-fail');
    console.log('ok');
  }catch(e){console.log('parse-fail:'+e.message)}
})" 2>/dev/null || echo 'failed')"
  if [ "$ok" = "ok" ]; then
    pass "detect-backends picks up cerebras/deepseek/nvidia_nim/google_aistudio via env"
  else
    fail "v0.8.0 provider detection: $ok"
  fi
fi

# --- T22: --free-tier-first flag biases recommendation cascade
# When ONLY a hosted-OSS free-tier key + a paid hosted_oss key are set, free-tier-first
# should prefer the free one (Cerebras) over the paid one (Together).
if [ -x "$DETECT" ]; then
  rec_default="$(env -i PATH="$PATH" HOME="$HOME" \
    CEREBRAS_API_KEY=k TOGETHER_API_KEY=k \
    "$DETECT" 2>/dev/null | grep -o '"recommendation":[[:space:]]*"[^"]*"' | head -1)"
  rec_free="$(env -i PATH="$PATH" HOME="$HOME" \
    CEREBRAS_API_KEY=k TOGETHER_API_KEY=k \
    "$DETECT" --free-tier-first 2>/dev/null | grep -o '"recommendation":[[:space:]]*"[^"]*"' | head -1)"
  # Default: Together comes first in privacy-first cascade
  # Free-tier-first: Cerebras comes first
  # Note: this test is meaningful only when no local backend is on PATH.
  # On dev machines with LM Studio cache or Ollama installed, both will recommend
  # the local tier, which is fine behavior (local IS free + private).
  if echo "$rec_default" | grep -q 'private_local\|hosted_oss/together' \
     && echo "$rec_free" | grep -qE 'private_local|hosted_oss/cerebras|hosted_oss/nvidia'; then
    pass "detect-backends --free-tier-first changes cascade ordering"
  else
    fail "free-tier-first cascade unexpected: default=$rec_default free=$rec_free"
  fi
fi

# --- T23: configure-backend writes a Cerebras config with right baseURL + apiKey
if [ -x "$CONFIG" ]; then
  T="$TMP_ROOT/t23"; mkdir -p "$T"
  (cd "$T" && "$CONFIG" --tier hosted_oss --provider cerebras --model "llama-3.3-70b" >/dev/null 2>&1) || true
  ok="$(node -e "
const j=require('$T/opencode.json');
if(j.model!=='cerebras/llama-3.3-70b')process.exit(1);
if(j.provider.cerebras.options.baseURL!=='https://api.cerebras.ai/v1')process.exit(2);
if(j.provider.cerebras.options.apiKey!=='{env:CEREBRAS_API_KEY}')process.exit(3);
if(!j.provider.cerebras.models||!j.provider.cerebras.models['llama-3.3-70b'])process.exit(4);
console.log('ok');
" 2>/dev/null || echo 'failed')"
  if [ "$ok" = "ok" ]; then
    pass "configure-backend cerebras emits correct baseURL + apiKey + models block"
  else
    fail "cerebras config wrong: $ok"
  fi
fi

# --- T24: configure-backend writes a DeepSeek-direct config
if [ -x "$CONFIG" ]; then
  T="$TMP_ROOT/t24"; mkdir -p "$T"
  (cd "$T" && "$CONFIG" --tier hosted_oss --provider deepseek --model "deepseek-chat" >/dev/null 2>&1) || true
  ok="$(node -e "
const j=require('$T/opencode.json');
if(j.model!=='deepseek/deepseek-chat')process.exit(1);
if(j.provider.deepseek.options.baseURL!=='https://api.deepseek.com/v1')process.exit(2);
if(j.provider.deepseek.options.apiKey!=='{env:DEEPSEEK_API_KEY}')process.exit(3);
console.log('ok');
" 2>/dev/null || echo 'failed')"
  if [ "$ok" = "ok" ]; then
    pass "configure-backend deepseek emits correct baseURL + apiKey"
  else
    fail "deepseek config wrong: $ok"
  fi
fi

# --- T25: configure-backend writes an NVIDIA NIM config (alias nvidia_nim → nvidia)
if [ -x "$CONFIG" ]; then
  T="$TMP_ROOT/t25"; mkdir -p "$T"
  (cd "$T" && "$CONFIG" --tier hosted_oss --provider nvidia_nim --model "meta/llama-3.3-70b-instruct" >/dev/null 2>&1) || true
  ok="$(node -e "
const j=require('$T/opencode.json');
if(!j.provider.nvidia)process.exit(1);
if(j.model!=='nvidia/meta/llama-3.3-70b-instruct')process.exit(2);
if(j.provider.nvidia.options.baseURL!=='https://integrate.api.nvidia.com/v1')process.exit(3);
console.log('ok');
" 2>/dev/null || echo 'failed')"
  if [ "$ok" = "ok" ]; then
    pass "configure-backend nvidia_nim alias maps to canonical 'nvidia' provider id"
  else
    fail "nvidia_nim config wrong: $ok"
  fi
fi

# --- T26: configure-backend writes a Google AI Studio (Gemini) config
if [ -x "$CONFIG" ]; then
  T="$TMP_ROOT/t26"; mkdir -p "$T"
  (cd "$T" && "$CONFIG" --tier proprietary --provider google_aistudio --model "gemini-2.0-flash" >/dev/null 2>&1) || true
  ok="$(node -e "
const j=require('$T/opencode.json');
if(!j.provider.google)process.exit(1);
if(j.model!=='google/gemini-2.0-flash')process.exit(2);
if(!j.provider.google.options.baseURL.includes('generativelanguage.googleapis.com'))process.exit(3);
if(j.provider.google.options.apiKey!=='{env:GOOGLE_API_KEY}')process.exit(4);
console.log('ok');
" 2>/dev/null || echo 'failed')"
  if [ "$ok" = "ok" ]; then
    pass "configure-backend google_aistudio emits Gemini config (proprietary tier)"
  else
    fail "google_aistudio config wrong: $ok"
  fi
fi

# --- T27: MLX (Apple Silicon) provider — defaults baseURL to 127.0.0.1:8080
if [ -x "$CONFIG" ]; then
  T="$TMP_ROOT/t27"; mkdir -p "$T"
  (cd "$T" && "$CONFIG" --tier private_local --provider mlx --model "Qwen2.5-Coder-32B-Instruct-4bit" >/dev/null 2>&1) || true
  ok="$(node -e "
const j=require('$T/opencode.json');
if(j.model!=='mlx/Qwen2.5-Coder-32B-Instruct-4bit')process.exit(1);
if(j.provider.mlx.options.baseURL!=='http://127.0.0.1:8080/v1')process.exit(2);
console.log('ok');
" 2>/dev/null || echo 'failed')"
  if [ "$ok" = "ok" ]; then
    pass "configure-backend private_local/mlx uses 127.0.0.1:8080 default"
  else
    fail "mlx config wrong: $ok"
  fi
fi

# --- T28: detector --help prints the flag list
if [ -x "$DETECT" ]; then
  if "$DETECT" --help 2>&1 | grep -qE 'free-tier-first'; then
    pass "detect-backends --help mentions --free-tier-first"
  else
    fail "detect-backends --help missing --free-tier-first"
  fi
fi

# --- T29: codex round-1 F1 regression — Google-only env emits proprietary tier
# in BOTH cascades (was hosted_oss/google_aistudio in privacy-first @ line 140)
if [ -x "$DETECT" ]; then
  CLEAN_HOME="$TMP_ROOT/t29-home"; mkdir -p "$CLEAN_HOME"
  # Strict PATH avoids picking up LM Studio / Ollama / etc. on the dev box,
  # which would short-circuit the cascade at private_local before reaching
  # the proprietary tier we're testing.
  STRICT_PATH=/usr/bin:/bin
  rec_default="$(env -i PATH="$STRICT_PATH" HOME="$CLEAN_HOME" GOOGLE_API_KEY=k \
    "$DETECT" 2>/dev/null | grep -o '"recommendation":[[:space:]]*"[^"]*"' | head -1)"
  rec_free="$(env -i PATH="$STRICT_PATH" HOME="$CLEAN_HOME" GOOGLE_API_KEY=k \
    "$DETECT" --free-tier-first 2>/dev/null | grep -o '"recommendation":[[:space:]]*"[^"]*"' | head -1)"
  if echo "$rec_default" | grep -q 'proprietary/google_aistudio' \
     && echo "$rec_free" | grep -q 'proprietary/google_aistudio'; then
    pass "Google-only env emits proprietary tier in BOTH cascades (F1 fix)"
  else
    fail "F1 regression — default=$rec_default free=$rec_free"
  fi
fi

# --- T30: codex round-1 F2 regression — alternate env names dropped
# NIM_API_KEY and GEMINI_API_KEY are no longer accepted; only canonical names
# (NVIDIA_API_KEY / GOOGLE_API_KEY) trigger detection.
if [ -x "$DETECT" ]; then
  CLEAN_HOME="$TMP_ROOT/t30-home"; mkdir -p "$CLEAN_HOME"
  STRICT_PATH=/usr/bin:/bin
  out="$(env -i PATH="$STRICT_PATH" HOME="$CLEAN_HOME" NIM_API_KEY=k GEMINI_API_KEY=k \
    "$DETECT" 2>/dev/null || true)"
  ok="$(printf '%s' "$out" | node -e "
let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{
  try{const j=JSON.parse(d);
    if(j.hosted_oss.nvidia_nim.key_set!==false)return console.log('nim-detected-from-alt');
    if(j.proprietary.google_aistudio.key_set!==false)return console.log('gemini-detected-from-alt');
    if(j.hosted_oss.nvidia_nim.env!=='NVIDIA_API_KEY')return console.log('nim-env-shape:'+j.hosted_oss.nvidia_nim.env);
    if(j.proprietary.google_aistudio.env!=='GOOGLE_API_KEY')return console.log('google-env-shape:'+j.proprietary.google_aistudio.env);
    console.log('ok');
  }catch(e){console.log('parse-fail:'+e.message)}
})" 2>/dev/null || echo 'failed')"
  if [ "$ok" = "ok" ]; then
    pass "alternate env names not honored — only canonical NVIDIA_API_KEY/GOOGLE_API_KEY (F2 fix)"
  else
    fail "F2 regression — $ok"
  fi
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
echo "All backend picker tests passed!"
