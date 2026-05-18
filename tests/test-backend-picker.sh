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

# --- v0.10.0 Mixed-Mode: configure-backend.sh learns --reviewer-tier /
# --reviewer-provider / --reviewer-model. When all three are supplied,
# the merged opencode.json gains an `agent.review.model` block plus the
# reviewer's provider block (if it differs from the coder's). Community
# patterns research (May 2026) showed 11/15 surveyed configs route
# review work to a different model than build work — opening with the
# coder/reviewer split first, --planner/--docs to follow.

# --- T31: --reviewer-* flags produce agent.review.model + reviewer provider block
if [ -x "$CONFIG" ]; then
  T="$TMP_ROOT/t31"; mkdir -p "$T"
  (cd "$T" && "$CONFIG" \
     --tier private_local --provider ollama --model qwen3-coder:30b \
     --reviewer-tier hosted_oss --reviewer-provider cerebras --reviewer-model gpt-oss-120b \
     >/dev/null 2>&1) || true
  if [ -f "$T/opencode.json" ]; then
    ok="$(node -e "
const j=require('$T/opencode.json');
if(j.model!=='ollama/qwen3-coder:30b'){console.log('coder-model-wrong:'+j.model);process.exit(1)}
if(!j.agent||!j.agent.review||!j.agent.review.model){console.log('missing-agent-review');process.exit(1)}
if(j.agent.review.model!=='cerebras/gpt-oss-120b'){console.log('reviewer-model-wrong:'+j.agent.review.model);process.exit(1)}
if(!j.provider||!j.provider.ollama){console.log('missing-coder-provider-block');process.exit(1)}
if(!j.provider.cerebras){console.log('missing-reviewer-provider-block');process.exit(1)}
if(!j.provider.cerebras.options||!String(j.provider.cerebras.options.baseURL||'').includes('cerebras.ai')){console.log('reviewer-baseurl-wrong');process.exit(1)}
console.log('ok');
" 2>/dev/null || echo 'failed')"
    if [ "$ok" = "ok" ]; then
      pass "Mixed-Mode: --reviewer-* writes agent.review.model + reviewer provider block"
    else
      fail "Mixed-Mode T31 — $ok"
    fi
  else
    fail "Mixed-Mode T31 — configure did not write opencode.json"
  fi
fi

# --- T32: without --reviewer-* flags, no agent.review block created (regression
#         guard — single-model pick must keep working unchanged)
if [ -x "$CONFIG" ]; then
  T="$TMP_ROOT/t32"; mkdir -p "$T"
  (cd "$T" && "$CONFIG" --tier private_local --provider ollama --model qwen3-coder:30b >/dev/null 2>&1) || true
  if [ -f "$T/opencode.json" ]; then
    ok="$(node -e "
const j=require('$T/opencode.json');
if(j.agent && j.agent.review){console.log('unexpected-agent-review');process.exit(1)}
console.log('ok');
" 2>/dev/null || echo 'failed')"
    if [ "$ok" = "ok" ]; then
      pass "single-model pick does NOT inject agent.review (Mixed-Mode opt-in only)"
    else
      fail "T32 — $ok"
    fi
  fi
fi

# --- T33: reviewer provider alias (e.g., nvidia_nim) resolves to canonical
#         (nvidia) in both the agent.review.model pin AND the provider block key
if [ -x "$CONFIG" ]; then
  T="$TMP_ROOT/t33"; mkdir -p "$T"
  (cd "$T" && "$CONFIG" \
     --tier proprietary --provider anthropic --model claude-opus-4-7 \
     --reviewer-tier hosted_oss --reviewer-provider nvidia_nim --reviewer-model deepseek-ai/deepseek-r1 \
     >/dev/null 2>&1) || true
  if [ -f "$T/opencode.json" ]; then
    ok="$(node -e "
const j=require('$T/opencode.json');
if(j.agent.review.model!=='nvidia/deepseek-ai/deepseek-r1'){console.log('alias-pin-wrong:'+j.agent.review.model);process.exit(1)}
if(!j.provider.nvidia){console.log('alias-provider-block-missing');process.exit(1)}
if(j.provider.nvidia_nim){console.log('non-canonical-key-present');process.exit(1)}
console.log('ok');
" 2>/dev/null || echo 'failed')"
    if [ "$ok" = "ok" ]; then
      pass "Mixed-Mode: --reviewer-provider alias resolves to canonical (nvidia_nim → nvidia)"
    else
      fail "T33 — $ok"
    fi
  fi
fi

# --- T34: same coder + reviewer provider (e.g., both anthropic) — single
#         provider block, agent.review.model still set
if [ -x "$CONFIG" ]; then
  T="$TMP_ROOT/t34"; mkdir -p "$T"
  (cd "$T" && "$CONFIG" \
     --tier proprietary --provider anthropic --model claude-haiku-4-5 \
     --reviewer-tier proprietary --reviewer-provider anthropic --reviewer-model claude-opus-4-7 \
     >/dev/null 2>&1) || true
  if [ -f "$T/opencode.json" ]; then
    ok="$(node -e "
const j=require('$T/opencode.json');
if(j.model!=='anthropic/claude-haiku-4-5'){console.log('coder-wrong:'+j.model);process.exit(1)}
if(j.agent.review.model!=='anthropic/claude-opus-4-7'){console.log('reviewer-wrong:'+j.agent.review.model);process.exit(1)}
if(Object.keys(j.provider).length!==1){console.log('expected-single-provider-got:'+Object.keys(j.provider).join(','));process.exit(1)}
console.log('ok');
" 2>/dev/null || echo 'failed')"
    if [ "$ok" = "ok" ]; then
      pass "Mixed-Mode: same provider for coder + reviewer → single provider block"
    else
      fail "T34 — $ok"
    fi
  fi
fi

# --- v0.10.1 Per-agent permission sandboxing. May-2026 community-patterns
# research: 9/15 surveyed opencode.json files use agent.<name>.permission.write
# to scope which paths each agent can touch — test-writer locked to test files,
# docs locked to .md, etc. Maps directly onto the wizard's SDLC steps.
# configure-backend exposes the two highest-signal sandboxes as boolean flags
# that inject canonical permission blocks; users wanting custom glob patterns
# edit opencode.json directly.

# --- T35: --sandbox-test-writer injects agent.test-writer.permission.write
#         restricting writes to test/spec files only
if [ -x "$CONFIG" ]; then
  T="$TMP_ROOT/t35"; mkdir -p "$T"
  (cd "$T" && "$CONFIG" \
     --tier private_local --provider ollama --model qwen3-coder:30b \
     --sandbox-test-writer >/dev/null 2>&1) || true
  if [ -f "$T/opencode.json" ]; then
    ok="$(node -e "
const j=require('$T/opencode.json');
const tw=j.agent && j.agent['test-writer'];
if(!tw||!tw.permission||!tw.permission.write){console.log('missing-test-writer-perm');process.exit(1)}
const w=tw.permission.write;
if(w['**/*.test.*']!=='allow'){console.log('missing-test-allow');process.exit(1)}
if(w['**/*.spec.*']!=='allow'){console.log('missing-spec-allow');process.exit(1)}
if(w['*']!=='deny'){console.log('missing-default-deny');process.exit(1)}
console.log('ok');
" 2>/dev/null || echo 'failed')"
    if [ "$ok" = "ok" ]; then
      pass "--sandbox-test-writer injects canonical permission.write block"
    else
      fail "T35 — $ok"
    fi
  fi
fi

# --- T36: --sandbox-docs injects agent.docs.permission.write
#         restricting writes to .md only
if [ -x "$CONFIG" ]; then
  T="$TMP_ROOT/t36"; mkdir -p "$T"
  (cd "$T" && "$CONFIG" \
     --tier private_local --provider ollama --model qwen3-coder:30b \
     --sandbox-docs >/dev/null 2>&1) || true
  if [ -f "$T/opencode.json" ]; then
    ok="$(node -e "
const j=require('$T/opencode.json');
const d=j.agent && j.agent.docs;
if(!d||!d.permission||!d.permission.write){console.log('missing-docs-perm');process.exit(1)}
const w=d.permission.write;
if(w['**/*.md']!=='allow'){console.log('missing-md-allow');process.exit(1)}
if(w['*']!=='deny'){console.log('missing-default-deny');process.exit(1)}
console.log('ok');
" 2>/dev/null || echo 'failed')"
    if [ "$ok" = "ok" ]; then
      pass "--sandbox-docs injects canonical permission.write block"
    else
      fail "T36 — $ok"
    fi
  fi
fi

# --- T37: both sandboxes compose, plus Mixed-Mode reviewer — full v0.10.x
#         hybrid in one invocation
if [ -x "$CONFIG" ]; then
  T="$TMP_ROOT/t37"; mkdir -p "$T"
  (cd "$T" && "$CONFIG" \
     --tier proprietary --provider anthropic --model claude-opus-4-7 \
     --reviewer-tier hosted_oss --reviewer-provider cerebras --reviewer-model gpt-oss-120b \
     --sandbox-test-writer --sandbox-docs >/dev/null 2>&1) || true
  if [ -f "$T/opencode.json" ]; then
    ok="$(node -e "
const j=require('$T/opencode.json');
if(j.agent.review.model!=='cerebras/gpt-oss-120b'){console.log('reviewer-wrong');process.exit(1)}
if(!j.agent['test-writer'].permission.write['**/*.test.*']){console.log('missing-tw-sandbox');process.exit(1)}
if(!j.agent.docs.permission.write['**/*.md']){console.log('missing-docs-sandbox');process.exit(1)}
console.log('ok');
" 2>/dev/null || echo 'failed')"
    if [ "$ok" = "ok" ]; then
      pass "v0.10.x hybrid: reviewer + test-writer sandbox + docs sandbox compose"
    else
      fail "T37 — $ok"
    fi
  fi
fi

# --- T38: sandbox flags absent → no agent.test-writer / agent.docs blocks
#         (regression guard — sandbox is opt-in only)
if [ -x "$CONFIG" ]; then
  T="$TMP_ROOT/t38"; mkdir -p "$T"
  (cd "$T" && "$CONFIG" --tier private_local --provider ollama --model qwen3-coder:30b >/dev/null 2>&1) || true
  if [ -f "$T/opencode.json" ]; then
    ok="$(node -e "
const j=require('$T/opencode.json');
if(j.agent && (j.agent['test-writer']||j.agent.docs)){console.log('unexpected-agent-block');process.exit(1)}
console.log('ok');
" 2>/dev/null || echo 'failed')"
    if [ "$ok" = "ok" ]; then
      pass "no sandbox flags → no test-writer/docs agent blocks (opt-in only)"
    else
      fail "T38 — $ok"
    fi
  fi
fi

# --- v0.10.2 Planner agent model routing. Community-patterns Q-A (May 2026):
# `plan` is the second-most-routed agent after `review` — typical split is
# plan=small/fast (haiku, gpt-5-mini, glm-4.5-air), build=mid, review=high.
# v0.10.2 mirrors the v0.10.0 reviewer flags for the planner agent.

# --- T39: --planner-* triplet writes agent.plan.model + planner provider block
if [ -x "$CONFIG" ]; then
  T="$TMP_ROOT/t39"; mkdir -p "$T"
  (cd "$T" && "$CONFIG" \
     --tier proprietary --provider anthropic --model claude-opus-4-7 \
     --planner-tier hosted_oss --planner-provider groq --planner-model llama-3.3-70b-versatile \
     >/dev/null 2>&1) || true
  if [ -f "$T/opencode.json" ]; then
    ok="$(node -e "
const j=require('$T/opencode.json');
if(j.model!=='anthropic/claude-opus-4-7'){console.log('coder-wrong:'+j.model);process.exit(1)}
if(!j.agent||!j.agent.plan||!j.agent.plan.model){console.log('missing-agent-plan');process.exit(1)}
if(j.agent.plan.model!=='groq/llama-3.3-70b-versatile'){console.log('plan-model-wrong:'+j.agent.plan.model);process.exit(1)}
if(!j.provider.anthropic){console.log('missing-coder-provider');process.exit(1)}
if(!j.provider.groq){console.log('missing-planner-provider');process.exit(1)}
console.log('ok');
" 2>/dev/null || echo 'failed')"
    if [ "$ok" = "ok" ]; then
      pass "Planner: --planner-* writes agent.plan.model + planner provider block"
    else
      fail "T39 — $ok"
    fi
  fi
fi

# --- T40: --reviewer-* + --planner-* compose — both agent blocks present
if [ -x "$CONFIG" ]; then
  T="$TMP_ROOT/t40"; mkdir -p "$T"
  (cd "$T" && "$CONFIG" \
     --tier proprietary --provider anthropic --model claude-sonnet-4-5 \
     --reviewer-tier proprietary --reviewer-provider anthropic --reviewer-model claude-opus-4-7 \
     --planner-tier hosted_oss --planner-provider cerebras --planner-model gpt-oss-120b \
     >/dev/null 2>&1) || true
  if [ -f "$T/opencode.json" ]; then
    ok="$(node -e "
const j=require('$T/opencode.json');
if(j.agent.review.model!=='anthropic/claude-opus-4-7'){console.log('reviewer-wrong');process.exit(1)}
if(j.agent.plan.model!=='cerebras/gpt-oss-120b'){console.log('plan-wrong:'+j.agent.plan.model);process.exit(1)}
if(!j.provider.cerebras){console.log('missing-planner-provider');process.exit(1)}
console.log('ok');
" 2>/dev/null || echo 'failed')"
    if [ "$ok" = "ok" ]; then
      pass "Planner + Reviewer compose — both agent blocks present, dual provider blocks"
    else
      fail "T40 — $ok"
    fi
  fi
fi

# --- T41: planner alias resolution (e.g., google_aistudio → google) parity
#         with reviewer side (matches v0.10.0 T33 pattern)
if [ -x "$CONFIG" ]; then
  T="$TMP_ROOT/t41"; mkdir -p "$T"
  (cd "$T" && "$CONFIG" \
     --tier proprietary --provider openai --model gpt-5 \
     --planner-tier proprietary --planner-provider google_aistudio --planner-model gemini-2.5-flash \
     >/dev/null 2>&1) || true
  if [ -f "$T/opencode.json" ]; then
    ok="$(node -e "
const j=require('$T/opencode.json');
if(j.agent.plan.model!=='google/gemini-2.5-flash'){console.log('alias-pin-wrong:'+j.agent.plan.model);process.exit(1)}
if(!j.provider.google){console.log('alias-provider-missing');process.exit(1)}
if(j.provider.google_aistudio){console.log('non-canonical-key-present');process.exit(1)}
console.log('ok');
" 2>/dev/null || echo 'failed')"
    if [ "$ok" = "ok" ]; then
      pass "Planner: --planner-provider alias resolves to canonical (google_aistudio → google)"
    else
      fail "T41 — $ok"
    fi
  fi
fi

# --- T42: partial --planner-* spec (e.g., --planner-tier alone) rejected
if [ -x "$CONFIG" ]; then
  T="$TMP_ROOT/t42"; mkdir -p "$T"
  rc=0
  (cd "$T" && "$CONFIG" \
     --tier private_local --provider ollama --model qwen3-coder:30b \
     --planner-tier hosted_oss >/dev/null 2>&1) || rc=$?
  if [ "$rc" -ne 0 ] && [ ! -f "$T/opencode.json" ]; then
    pass "partial --planner-* spec rejected without writing opencode.json"
  else
    fail "T42 — partial planner spec was accepted (rc=$rc)"
  fi
fi

# --- T43: no --planner-* → no agent.plan block (regression guard, opt-in only)
if [ -x "$CONFIG" ]; then
  T="$TMP_ROOT/t43"; mkdir -p "$T"
  (cd "$T" && "$CONFIG" --tier private_local --provider ollama --model qwen3-coder:30b >/dev/null 2>&1) || true
  if [ -f "$T/opencode.json" ]; then
    ok="$(node -e "
const j=require('$T/opencode.json');
if(j.agent && j.agent.plan){console.log('unexpected-agent-plan');process.exit(1)}
console.log('ok');
" 2>/dev/null || echo 'failed')"
    if [ "$ok" = "ok" ]; then
      pass "no --planner-* → no agent.plan block (opt-in only)"
    else
      fail "T43 — $ok"
    fi
  fi
fi

# --- v0.10.4 small_model: global fast/cheap fallback. May-17 research found
# 35-40% of community configs set this top-level field. Distinct from
# agent.plan.model (which only affects plan-mode tasks) — small_model is
# the cross-cutting "use this when the call is cheap" hint. Flags mirror
# the reviewer/planner triplet shape: --small-tier T --small-provider P
# [--small-model M, optional; filled from default-model map].

# --- T44: --small-* triplet writes top-level small_model + small provider block
if [ -x "$CONFIG" ]; then
  T="$TMP_ROOT/t44"; mkdir -p "$T"
  (cd "$T" && "$CONFIG" \
     --tier proprietary --provider anthropic --model claude-opus-4-7 \
     --small-tier proprietary --small-provider anthropic --small-model claude-haiku-4-5 \
     >/dev/null 2>&1) || true
  if [ -f "$T/opencode.json" ]; then
    ok="$(node -e "
const j=require('$T/opencode.json');
if(j.model!=='anthropic/claude-opus-4-7'){console.log('coder-wrong:'+j.model);process.exit(1)}
if(j.small_model!=='anthropic/claude-haiku-4-5'){console.log('small_model-wrong:'+j.small_model);process.exit(1)}
console.log('ok');
" 2>/dev/null || echo 'failed')"
    if [ "$ok" = "ok" ]; then
      pass "--small-* writes top-level small_model pin"
    else
      fail "T44 — $ok"
    fi
  fi
fi

# --- T45: --small-* uses canonical alias (e.g., google_aistudio → google)
if [ -x "$CONFIG" ]; then
  T="$TMP_ROOT/t45"; mkdir -p "$T"
  (cd "$T" && "$CONFIG" \
     --tier proprietary --provider anthropic --model claude-opus-4-7 \
     --small-tier proprietary --small-provider google_aistudio --small-model gemini-2.5-flash \
     >/dev/null 2>&1) || true
  if [ -f "$T/opencode.json" ]; then
    ok="$(node -e "
const j=require('$T/opencode.json');
if(j.small_model!=='google/gemini-2.5-flash'){console.log('alias-pin-wrong:'+j.small_model);process.exit(1)}
if(!j.provider.google){console.log('alias-provider-missing');process.exit(1)}
console.log('ok');
" 2>/dev/null || echo 'failed')"
    if [ "$ok" = "ok" ]; then
      pass "--small-provider alias resolves to canonical (google_aistudio → google)"
    else
      fail "T45 — $ok"
    fi
  fi
fi

# --- T46: --small-* composes with --reviewer-* + --planner-* + --sandbox-*
if [ -x "$CONFIG" ]; then
  T="$TMP_ROOT/t46"; mkdir -p "$T"
  (cd "$T" && "$CONFIG" \
     --tier proprietary --provider anthropic --model claude-opus-4-7 \
     --small-tier proprietary --small-provider anthropic --small-model claude-haiku-4-5 \
     --reviewer-tier hosted_oss --reviewer-provider cerebras --reviewer-model gpt-oss-120b \
     --planner-tier hosted_oss --planner-provider groq --planner-model gpt-oss-120b \
     --sandbox-test-writer --sandbox-docs >/dev/null 2>&1) || true
  if [ -f "$T/opencode.json" ]; then
    ok="$(node -e "
const j=require('$T/opencode.json');
if(j.small_model!=='anthropic/claude-haiku-4-5'){console.log('small-wrong');process.exit(1)}
if(j.agent.review.model!=='cerebras/gpt-oss-120b'){console.log('rev-wrong');process.exit(1)}
if(j.agent.plan.model!=='groq/gpt-oss-120b'){console.log('plan-wrong');process.exit(1)}
if(!j.agent['test-writer'].permission.write){console.log('tw-wrong');process.exit(1)}
console.log('ok');
" 2>/dev/null || echo 'failed')"
    if [ "$ok" = "ok" ]; then
      pass "Full v0.10.x: --small-* + --reviewer-* + --planner-* + --sandbox-* all compose"
    else
      fail "T46 — $ok"
    fi
  fi
fi

# --- T47: partial --small-* spec rejected (all-or-nothing triplet)
if [ -x "$CONFIG" ]; then
  T="$TMP_ROOT/t47"; mkdir -p "$T"
  rc=0
  (cd "$T" && "$CONFIG" \
     --tier private_local --provider ollama --model qwen3-coder:30b \
     --small-tier proprietary >/dev/null 2>&1) || rc=$?
  if [ "$rc" -ne 0 ] && [ ! -f "$T/opencode.json" ]; then
    pass "partial --small-* spec rejected without writing opencode.json"
  else
    fail "T47 — partial small spec accepted (rc=$rc)"
  fi
fi

# --- T48: no --small-* → no top-level small_model field (opt-in only)
if [ -x "$CONFIG" ]; then
  T="$TMP_ROOT/t48"; mkdir -p "$T"
  (cd "$T" && "$CONFIG" --tier private_local --provider ollama --model qwen3-coder:30b >/dev/null 2>&1) || true
  if [ -f "$T/opencode.json" ]; then
    ok="$(node -e "
const j=require('$T/opencode.json');
if('small_model' in j){console.log('unexpected-small_model');process.exit(1)}
console.log('ok');
" 2>/dev/null || echo 'failed')"
    if [ "$ok" = "ok" ]; then
      pass "no --small-* → no small_model field (opt-in regression guard)"
    else
      fail "T48 — $ok"
    fi
  fi
fi

# --- v0.10.5 --sandbox-plan: plan-mode tool denial. Community pattern
# (33% adoption per May-17 research): plan agent has tools.write/edit/patch
# all set to false so the planner can read + reason but not modify code.
# Distinct from v0.10.1 permission.write sandboxes — those are path-scoped
# allow/deny on file writes; this is a categorical tool disablement.

# --- T49: --sandbox-plan injects agent.plan.tools with all-false denial
if [ -x "$CONFIG" ]; then
  T="$TMP_ROOT/t49"; mkdir -p "$T"
  (cd "$T" && "$CONFIG" \
     --tier private_local --provider ollama --model qwen3-coder:30b \
     --sandbox-plan >/dev/null 2>&1) || true
  if [ -f "$T/opencode.json" ]; then
    ok="$(node -e "
const j=require('$T/opencode.json');
const p=j.agent && j.agent.plan;
if(!p||!p.tools){console.log('missing-plan-tools');process.exit(1)}
if(p.tools.write!==false){console.log('write-not-false:'+p.tools.write);process.exit(1)}
if(p.tools.edit!==false){console.log('edit-not-false');process.exit(1)}
if(p.tools.patch!==false){console.log('patch-not-false');process.exit(1)}
console.log('ok');
" 2>/dev/null || echo 'failed')"
    if [ "$ok" = "ok" ]; then
      pass "--sandbox-plan injects agent.plan.tools (write/edit/patch all false)"
    else
      fail "T49 — $ok"
    fi
  fi
fi

# --- T50: --sandbox-plan + --planner-* compose — both model AND tools in agent.plan
if [ -x "$CONFIG" ]; then
  T="$TMP_ROOT/t50"; mkdir -p "$T"
  (cd "$T" && "$CONFIG" \
     --tier proprietary --provider anthropic --model claude-opus-4-7 \
     --planner-tier hosted_oss --planner-provider groq --planner-model gpt-oss-120b \
     --sandbox-plan >/dev/null 2>&1) || true
  if [ -f "$T/opencode.json" ]; then
    ok="$(node -e "
const j=require('$T/opencode.json');
if(j.agent.plan.model!=='groq/gpt-oss-120b'){console.log('plan-model-wrong:'+j.agent.plan.model);process.exit(1)}
if(j.agent.plan.tools.write!==false){console.log('plan-tools-wrong');process.exit(1)}
console.log('ok');
" 2>/dev/null || echo 'failed')"
    if [ "$ok" = "ok" ]; then
      pass "--sandbox-plan + --planner-* compose (agent.plan has both model AND tools)"
    else
      fail "T50 — $ok"
    fi
  fi
fi

# --- T51: all three sandboxes (plan/test-writer/docs) compose in one call
if [ -x "$CONFIG" ]; then
  T="$TMP_ROOT/t51"; mkdir -p "$T"
  (cd "$T" && "$CONFIG" \
     --tier private_local --provider ollama --model qwen3-coder:30b \
     --sandbox-plan --sandbox-test-writer --sandbox-docs >/dev/null 2>&1) || true
  if [ -f "$T/opencode.json" ]; then
    ok="$(node -e "
const j=require('$T/opencode.json');
if(!j.agent.plan||!j.agent.plan.tools){console.log('no-plan-sandbox');process.exit(1)}
if(!j.agent['test-writer']||!j.agent['test-writer'].permission){console.log('no-tw-sandbox');process.exit(1)}
if(!j.agent.docs||!j.agent.docs.permission){console.log('no-docs-sandbox');process.exit(1)}
console.log('ok');
" 2>/dev/null || echo 'failed')"
    if [ "$ok" = "ok" ]; then
      pass "all three sandboxes (plan/test-writer/docs) compose"
    else
      fail "T51 — $ok"
    fi
  fi
fi

# --- T52: no --sandbox-plan → no agent.plan.tools block (opt-in regression)
if [ -x "$CONFIG" ]; then
  T="$TMP_ROOT/t52"; mkdir -p "$T"
  (cd "$T" && "$CONFIG" --tier private_local --provider ollama --model qwen3-coder:30b >/dev/null 2>&1) || true
  if [ -f "$T/opencode.json" ]; then
    ok="$(node -e "
const j=require('$T/opencode.json');
if(j.agent && j.agent.plan && j.agent.plan.tools){console.log('unexpected-plan-tools');process.exit(1)}
console.log('ok');
" 2>/dev/null || echo 'failed')"
    if [ "$ok" = "ok" ]; then
      pass "no --sandbox-plan → no agent.plan.tools block (opt-in regression guard)"
    else
      fail "T52 — $ok"
    fi
  fi
fi

# --- v0.11.0: Z.AI GLM Coding Plan as proprietary tier entry.
# Most-cited post-Anthropic-OAuth-ban migration target per May-2026
# community research. Closed weights (GLM) but OpenAI-compatible at
# api.z.ai/api/paas/v4. Default model: glm-4.6 (most-documented stable
# release as of May 2026).

# --- T53: configure-backend writes correct Z.AI provider block
if [ -x "$CONFIG" ]; then
  T="$TMP_ROOT/t53"; mkdir -p "$T"
  (cd "$T" && "$CONFIG" --tier proprietary --provider zai --model "glm-4.6" >/dev/null 2>&1) || true
  if [ -f "$T/opencode.json" ]; then
    ok="$(node -e "
const j=require('$T/opencode.json');
if(j.model!=='zai/glm-4.6'){console.log('model-wrong:'+j.model);process.exit(1)}
if(!j.provider||!j.provider.zai){console.log('missing-zai-block');process.exit(1)}
const opts=j.provider.zai.options||{};
if(opts.apiKey!=='{env:ZAI_API_KEY}'){console.log('wrong-apikey:'+opts.apiKey);process.exit(1)}
if(!String(opts.baseURL||'').includes('api.z.ai')){console.log('wrong-baseurl:'+opts.baseURL);process.exit(1)}
if(j.provider.zai.npm!=='@ai-sdk/openai-compatible'){console.log('wrong-npm');process.exit(1)}
if(!j.provider.zai.models||!j.provider.zai.models['glm-4.6']){console.log('missing-model-entry');process.exit(1)}
console.log('ok');
" 2>/dev/null || echo 'failed')"
    if [ "$ok" = "ok" ]; then
      pass "configure-backend writes Z.AI provider block (proprietary/zai, glm-4.6)"
    else
      fail "T53 — $ok"
    fi
  fi
fi

# --- T54: Z.AI aliases (z.ai, z_ai, glm) all resolve to canonical 'zai'
if [ -x "$CONFIG" ]; then
  T="$TMP_ROOT/t54"; mkdir -p "$T"
  (cd "$T" && "$CONFIG" --tier proprietary --provider glm --model "glm-4.6" >/dev/null 2>&1) || true
  if [ -f "$T/opencode.json" ]; then
    ok="$(node -e "
const j=require('$T/opencode.json');
if(j.model!=='zai/glm-4.6'){console.log('alias-pin-wrong:'+j.model);process.exit(1)}
if(!j.provider.zai){console.log('alias-block-missing');process.exit(1)}
if(j.provider.glm){console.log('non-canonical-key-present');process.exit(1)}
console.log('ok');
" 2>/dev/null || echo 'failed')"
    if [ "$ok" = "ok" ]; then
      pass "Z.AI alias 'glm' resolves to canonical 'zai' provider id"
    else
      fail "T54 — $ok"
    fi
  fi
fi

# --- T55: detect-backends picks up ZAI_API_KEY and emits proprietary/zai
# Use a clean HOME so the host's LM Studio cache (~/.cache/lm-studio) doesn't
# trigger a private_local recommendation that would beat the proprietary tier.
if [ -x "$DETECT" ]; then
  FAKE_HOME="$TMP_ROOT/t55-home"; mkdir -p "$FAKE_HOME"
  # Strip PATH to a minimum so local runtime binaries (ollama, vllm, mlx_lm) on
  # the host don't get detected — we want ZAI_API_KEY to be the ONLY signal.
  ok="$(env -i HOME="$FAKE_HOME" PATH="/usr/bin:/bin" ZAI_API_KEY="x" "$DETECT" 2>/dev/null | node -e "
let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{
  try{const j=JSON.parse(d);
    if(!j.proprietary.zai){console.log('no-zai-block');process.exit(1)}
    if(j.proprietary.zai.key_set!==true){console.log('not-detected');process.exit(1)}
    if(j.proprietary.zai.env!=='ZAI_API_KEY'){console.log('wrong-env:'+j.proprietary.zai.env);process.exit(1)}
    if(j.recommendation!=='proprietary/zai'){console.log('not-recommended:'+j.recommendation);process.exit(1)}
    console.log('ok');
  }catch(e){console.log('parse-fail:'+e.message)}
})" 2>/dev/null || echo 'failed')"
  if [ "$ok" = "ok" ]; then
    pass "detect-backends picks up ZAI_API_KEY and recommends proprietary/zai"
  else
    fail "T55 — $ok"
  fi
fi

# --- v0.11.1: per-agent temperatures. May-2026 community pattern (joelhooks
# + ppries gists, others): plan=0.1 (deterministic), build=0.3 (some
# creativity), review=0.1 (deterministic). Flags --planner-temp / --reviewer-
# temp / --coder-temp set agent.<name>.temperature; deep-merges with v0.10.0
# agent.review.model + v0.10.2 agent.plan.model + v0.10.5 agent.plan.tools.

# --- T56: --coder-temp writes agent.build.temperature ("build" is OpenCode's
#         default agent name for code generation work)
if [ -x "$CONFIG" ]; then
  T="$TMP_ROOT/t56"; mkdir -p "$T"
  (cd "$T" && "$CONFIG" \
     --tier private_local --provider ollama --model qwen3-coder:30b \
     --coder-temp 0.3 >/dev/null 2>&1) || true
  if [ -f "$T/opencode.json" ]; then
    ok="$(node -e "
const j=require('$T/opencode.json');
if(!j.agent||!j.agent.build||j.agent.build.temperature!==0.3){console.log('build-temp-wrong:'+JSON.stringify(j.agent&&j.agent.build));process.exit(1)}
console.log('ok');
" 2>/dev/null || echo 'failed')"
    if [ "$ok" = "ok" ]; then
      pass "--coder-temp 0.3 writes agent.build.temperature = 0.3"
    else
      fail "T56 — $ok"
    fi
  fi
fi

# --- T57: --reviewer-temp + --reviewer-* compose (model AND temperature both
#         present on agent.review)
if [ -x "$CONFIG" ]; then
  T="$TMP_ROOT/t57"; mkdir -p "$T"
  (cd "$T" && "$CONFIG" \
     --tier proprietary --provider anthropic --model claude-opus-4-7 \
     --reviewer-tier hosted_oss --reviewer-provider cerebras --reviewer-model gpt-oss-120b \
     --reviewer-temp 0.1 >/dev/null 2>&1) || true
  if [ -f "$T/opencode.json" ]; then
    ok="$(node -e "
const j=require('$T/opencode.json');
if(j.agent.review.model!=='cerebras/gpt-oss-120b'){console.log('rev-model-wrong');process.exit(1)}
if(j.agent.review.temperature!==0.1){console.log('rev-temp-wrong:'+j.agent.review.temperature);process.exit(1)}
console.log('ok');
" 2>/dev/null || echo 'failed')"
    if [ "$ok" = "ok" ]; then
      pass "--reviewer-temp composes with --reviewer-* (agent.review has model + temperature)"
    else
      fail "T57 — $ok"
    fi
  fi
fi

# --- T58: --planner-temp + --planner-* + --sandbox-plan compose
#         (agent.plan ends up with .model AND .temperature AND .tools)
if [ -x "$CONFIG" ]; then
  T="$TMP_ROOT/t58"; mkdir -p "$T"
  (cd "$T" && "$CONFIG" \
     --tier proprietary --provider anthropic --model claude-opus-4-7 \
     --planner-tier hosted_oss --planner-provider groq --planner-model gpt-oss-120b \
     --planner-temp 0.1 \
     --sandbox-plan >/dev/null 2>&1) || true
  if [ -f "$T/opencode.json" ]; then
    ok="$(node -e "
const j=require('$T/opencode.json');
if(j.agent.plan.model!=='groq/gpt-oss-120b'){console.log('plan-model-wrong');process.exit(1)}
if(j.agent.plan.temperature!==0.1){console.log('plan-temp-wrong');process.exit(1)}
if(j.agent.plan.tools.write!==false){console.log('plan-tools-wrong');process.exit(1)}
console.log('ok');
" 2>/dev/null || echo 'failed')"
    if [ "$ok" = "ok" ]; then
      pass "Full plan agent: --planner-* + --planner-temp + --sandbox-plan all compose"
    else
      fail "T58 — $ok"
    fi
  fi
fi

# --- T59: all three temp flags + all per-agent flags + sandboxes compose
if [ -x "$CONFIG" ]; then
  T="$TMP_ROOT/t59"; mkdir -p "$T"
  (cd "$T" && "$CONFIG" \
     --tier proprietary --provider anthropic --model claude-opus-4-7 \
     --coder-temp 0.3 \
     --reviewer-tier hosted_oss --reviewer-provider cerebras --reviewer-model gpt-oss-120b \
     --reviewer-temp 0.1 \
     --planner-tier hosted_oss --planner-provider groq --planner-model gpt-oss-120b \
     --planner-temp 0.1 >/dev/null 2>&1) || true
  if [ -f "$T/opencode.json" ]; then
    ok="$(node -e "
const j=require('$T/opencode.json');
if(j.agent.build.temperature!==0.3){console.log('build-temp');process.exit(1)}
if(j.agent.review.temperature!==0.1){console.log('rev-temp');process.exit(1)}
if(j.agent.plan.temperature!==0.1){console.log('plan-temp');process.exit(1)}
console.log('ok');
" 2>/dev/null || echo 'failed')"
    if [ "$ok" = "ok" ]; then
      pass "all three --*-temp flags emit correct agent.<name>.temperature values"
    else
      fail "T59 — $ok"
    fi
  fi
fi

# --- T60: no temp flags → no temperature fields written (opt-in regression)
if [ -x "$CONFIG" ]; then
  T="$TMP_ROOT/t60"; mkdir -p "$T"
  (cd "$T" && "$CONFIG" --tier private_local --provider ollama --model qwen3-coder:30b >/dev/null 2>&1) || true
  if [ -f "$T/opencode.json" ]; then
    ok="$(node -e "
const j=require('$T/opencode.json');
const agent=j.agent||{};
for(const k of ['build','plan','review']){
  if(agent[k]&&'temperature' in agent[k]){console.log('unexpected-temp:'+k);process.exit(1)}
}
console.log('ok');
" 2>/dev/null || echo 'failed')"
    if [ "$ok" = "ok" ]; then
      pass "no --*-temp flags → no temperature fields (opt-in regression guard)"
    else
      fail "T60 — $ok"
    fi
  fi
fi

# --- v0.11.2: security agent — full set (--security-* triplet for the
# model plus --sandbox-security for tool denial and --security-temp).
# Mirrors planner pattern: v0.10.2 --planner-* + v0.10.5 --sandbox-plan +
# v0.11.1 --planner-temp. Joelhooks-pattern security agent dedicates a
# specific model to "is this code safe" reviews with the same write/edit/
# patch denial as plan-mode.

# --- T61: --security-* writes agent.security.model + security provider block
if [ -x "$CONFIG" ]; then
  T="$TMP_ROOT/t61"; mkdir -p "$T"
  (cd "$T" && "$CONFIG" \
     --tier proprietary --provider anthropic --model claude-opus-4-7 \
     --security-tier proprietary --security-provider openai --security-model gpt-5.3-codex \
     >/dev/null 2>&1) || true
  if [ -f "$T/opencode.json" ]; then
    ok="$(node -e "
const j=require('$T/opencode.json');
if(j.agent.security.model!=='openai/gpt-5.3-codex'){console.log('sec-model-wrong:'+j.agent.security.model);process.exit(1)}
if(!j.provider.openai){console.log('missing-sec-provider');process.exit(1)}
console.log('ok');
" 2>/dev/null || echo 'failed')"
    if [ "$ok" = "ok" ]; then
      pass "--security-* writes agent.security.model + security provider block"
    else
      fail "T61 — $ok"
    fi
  fi
fi

# --- T62: --sandbox-security injects agent.security.tools.{write,edit,patch}=false
if [ -x "$CONFIG" ]; then
  T="$TMP_ROOT/t62"; mkdir -p "$T"
  (cd "$T" && "$CONFIG" \
     --tier private_local --provider ollama --model qwen3-coder:30b \
     --sandbox-security >/dev/null 2>&1) || true
  if [ -f "$T/opencode.json" ]; then
    ok="$(node -e "
const j=require('$T/opencode.json');
const s=j.agent && j.agent.security;
if(!s||!s.tools){console.log('missing-sec-tools');process.exit(1)}
if(s.tools.write!==false||s.tools.edit!==false||s.tools.patch!==false){console.log('sec-tools-wrong');process.exit(1)}
console.log('ok');
" 2>/dev/null || echo 'failed')"
    if [ "$ok" = "ok" ]; then
      pass "--sandbox-security injects agent.security.tools (write/edit/patch all false)"
    else
      fail "T62 — $ok"
    fi
  fi
fi

# --- T63: --security-* + --sandbox-security + --security-temp triple-compose
#         (agent.security gets .model AND .tools AND .temperature)
if [ -x "$CONFIG" ]; then
  T="$TMP_ROOT/t63"; mkdir -p "$T"
  (cd "$T" && "$CONFIG" \
     --tier proprietary --provider anthropic --model claude-opus-4-7 \
     --security-tier proprietary --security-provider openai --security-model gpt-5.3-codex \
     --security-temp 0.1 \
     --sandbox-security >/dev/null 2>&1) || true
  if [ -f "$T/opencode.json" ]; then
    ok="$(node -e "
const j=require('$T/opencode.json');
const s=j.agent.security;
if(s.model!=='openai/gpt-5.3-codex'){console.log('model-wrong');process.exit(1)}
if(s.temperature!==0.1){console.log('temp-wrong');process.exit(1)}
if(s.tools.write!==false){console.log('tools-wrong');process.exit(1)}
console.log('ok');
" 2>/dev/null || echo 'failed')"
    if [ "$ok" = "ok" ]; then
      pass "Full security agent: --security-* + --security-temp + --sandbox-security compose"
    else
      fail "T63 — $ok"
    fi
  fi
fi

# --- T64: partial --security-* spec rejected
if [ -x "$CONFIG" ]; then
  T="$TMP_ROOT/t64"; mkdir -p "$T"
  rc=0
  (cd "$T" && "$CONFIG" \
     --tier private_local --provider ollama --model qwen3-coder:30b \
     --security-tier proprietary >/dev/null 2>&1) || rc=$?
  if [ "$rc" -ne 0 ] && [ ! -f "$T/opencode.json" ]; then
    pass "partial --security-* spec rejected without writing opencode.json"
  else
    fail "T64 — partial security spec accepted (rc=$rc)"
  fi
fi

# --- T65: no security flags → no agent.security block (opt-in regression)
if [ -x "$CONFIG" ]; then
  T="$TMP_ROOT/t65"; mkdir -p "$T"
  (cd "$T" && "$CONFIG" --tier private_local --provider ollama --model qwen3-coder:30b >/dev/null 2>&1) || true
  if [ -f "$T/opencode.json" ]; then
    ok="$(node -e "
const j=require('$T/opencode.json');
if(j.agent && j.agent.security){console.log('unexpected-security');process.exit(1)}
console.log('ok');
" 2>/dev/null || echo 'failed')"
    if [ "$ok" = "ok" ]; then
      pass "no --security-* / --sandbox-security flags → no agent.security block"
    else
      fail "T65 — $ok"
    fi
  fi
fi

# --- v0.12.0: OpenCode Zen as new 5th "managed" tier. Vendor-routed PAYG
# over 40+ models including a free tier. Provider id `opencode` (per Zen's
# own docs — model pin format `opencode/<model>`). Aliases: opencode_zen,
# opencode-zen, zen. baseURL https://opencode.ai/zen/v1, env OPENCODE_ZEN_API_KEY.

# --- T66: configure-backend writes correct OpenCode Zen provider block
if [ -x "$CONFIG" ]; then
  T="$TMP_ROOT/t66"; mkdir -p "$T"
  (cd "$T" && "$CONFIG" --tier managed --provider opencode --model "gpt-5.5" >/dev/null 2>&1) || true
  if [ -f "$T/opencode.json" ]; then
    ok="$(node -e "
const j=require('$T/opencode.json');
if(j.model!=='opencode/gpt-5.5'){console.log('model-wrong:'+j.model);process.exit(1)}
if(!j.provider||!j.provider.opencode){console.log('missing-opencode-block');process.exit(1)}
const opts=j.provider.opencode.options||{};
if(opts.apiKey!=='{env:OPENCODE_ZEN_API_KEY}'){console.log('wrong-apikey:'+opts.apiKey);process.exit(1)}
if(opts.baseURL!=='https://opencode.ai/zen/v1'){console.log('wrong-baseurl:'+opts.baseURL);process.exit(1)}
if(j.provider.opencode.npm!=='@ai-sdk/openai-compatible'){console.log('wrong-npm');process.exit(1)}
if(!j.provider.opencode.models||!j.provider.opencode.models['gpt-5.5']){console.log('missing-model-entry');process.exit(1)}
console.log('ok');
" 2>/dev/null || echo 'failed')"
    if [ "$ok" = "ok" ]; then
      pass "configure-backend writes OpenCode Zen provider block (managed/opencode, gpt-5.5)"
    else
      fail "T66 — $ok"
    fi
  fi
fi

# --- T67: Zen aliases (zen, opencode_zen, opencode-zen) resolve to canonical 'opencode'
if [ -x "$CONFIG" ]; then
  T="$TMP_ROOT/t67"; mkdir -p "$T"
  (cd "$T" && "$CONFIG" --tier managed --provider zen --model "gpt-5.5" >/dev/null 2>&1) || true
  if [ -f "$T/opencode.json" ]; then
    ok="$(node -e "
const j=require('$T/opencode.json');
if(j.model!=='opencode/gpt-5.5'){console.log('alias-pin-wrong:'+j.model);process.exit(1)}
if(!j.provider.opencode){console.log('alias-block-missing');process.exit(1)}
if(j.provider.zen){console.log('non-canonical-key-present');process.exit(1)}
console.log('ok');
" 2>/dev/null || echo 'failed')"
    if [ "$ok" = "ok" ]; then
      pass "OpenCode Zen alias 'zen' resolves to canonical 'opencode' provider id"
    else
      fail "T67 — $ok"
    fi
  fi
fi

# --- T68: detect-backends picks up OPENCODE_ZEN_API_KEY and emits managed/opencode
if [ -x "$DETECT" ]; then
  FAKE_HOME="$TMP_ROOT/t68-home"; mkdir -p "$FAKE_HOME"
  ok="$(env -i HOME="$FAKE_HOME" PATH="/usr/bin:/bin" OPENCODE_ZEN_API_KEY="x" "$DETECT" 2>/dev/null | node -e "
let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{
  try{const j=JSON.parse(d);
    if(!j.managed||!j.managed.opencode){console.log('no-managed-block');process.exit(1)}
    if(j.managed.opencode.key_set!==true){console.log('not-detected');process.exit(1)}
    if(j.managed.opencode.env!=='OPENCODE_ZEN_API_KEY'){console.log('wrong-env');process.exit(1)}
    if(j.recommendation!=='managed/opencode'){console.log('not-recommended:'+j.recommendation);process.exit(1)}
    console.log('ok');
  }catch(e){console.log('parse-fail:'+e.message)}
})" 2>/dev/null || echo 'failed')"
  if [ "$ok" = "ok" ]; then
    pass "detect-backends picks up OPENCODE_ZEN_API_KEY and recommends managed/opencode"
  else
    fail "T68 — $ok"
  fi
fi

# --- T69: managed tier composes with all v0.10.x/v0.11.x agent flags
#         (the entire flag surface should work on the new tier too)
if [ -x "$CONFIG" ]; then
  T="$TMP_ROOT/t69"; mkdir -p "$T"
  (cd "$T" && "$CONFIG" \
     --tier managed --provider opencode --model gpt-5.5 \
     --reviewer-tier managed --reviewer-provider opencode --reviewer-model claude-opus-4-7 \
     --sandbox-test-writer --coder-temp 0.3 >/dev/null 2>&1) || true
  if [ -f "$T/opencode.json" ]; then
    ok="$(node -e "
const j=require('$T/opencode.json');
if(j.model!=='opencode/gpt-5.5'){console.log('coder-wrong');process.exit(1)}
if(j.agent.review.model!=='opencode/claude-opus-4-7'){console.log('rev-wrong:'+j.agent.review.model);process.exit(1)}
if(j.agent.build.temperature!==0.3){console.log('temp-wrong');process.exit(1)}
if(!j.agent['test-writer']){console.log('no-tw');process.exit(1)}
// Both coder and reviewer use same provider (opencode) — single provider block
if(Object.keys(j.provider).length!==1){console.log('expected-single-provider-got:'+Object.keys(j.provider).join(','));process.exit(1)}
console.log('ok');
" 2>/dev/null || echo 'failed')"
    if [ "$ok" = "ok" ]; then
      pass "managed/opencode composes with --reviewer-* / --sandbox-* / --*-temp (full v0.11.x surface)"
    else
      fail "T69 — $ok"
    fi
  fi
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
echo "All backend picker tests passed!"
