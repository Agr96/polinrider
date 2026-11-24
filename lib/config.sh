# lib/config.sh — allowlist-only dotenv loader. Never `source`s a config file.

CFG_CONFIG_FILE=""
CFG_SIGNATURES_FILE=""
CFG_CANARY_FILE=""
CONFIG_EXPLICIT=0

# Expand a limited subset of parameter forms WITHOUT executing anything:
# ${VAR}, ${VAR:-word} and $VAR. Unknown names expand to the empty string.
_expand_value() {
  local v=$1 out="" rest m name def val prefix tail
  while [[ "$v" == *'${'* ]]; do
    out+="${v%%\$\{*}"
    rest="${v#*\$\{}"
    if [[ "$rest" != *'}'* ]]; then
      out+='${'
      v="$rest"
      break
    fi
    m="${rest%%\}*}"
    v="${rest#*\}}"
    if [[ "$m" == *':-'* ]]; then
      name="${m%%:-*}"
      def="${m#*:-}"
    else
      name="$m"
      def=""
    fi
    if [[ "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
      val="${!name-}"
      [[ -z "$val" ]] && val="$def"
      out+="$val"
    else
      out+='${'"$m"'}' 
    fi
  done
  v="$out$v"
  while [[ "$v" == *'$'* ]]; do
    if [[ "$v" =~ ^([^\$]*)(\$)([A-Za-z_][A-Za-z0-9_]*)?(.*)$ ]]; then
      prefix="${BASH_REMATCH[1]}"
      name="${BASH_REMATCH[3]}"
      tail="${BASH_REMATCH[4]}"
      if [[ -z "$name" ]]; then
        out+="$prefix\$"
        v="$tail"
      else
        out+="$prefix${!name-}"
        v="$tail"
      fi
    else
      break
    fi
  done
  out+="$v"
  printf '%s' "$out"
}

# _parse_env_file <path> <scope: config|sig|canary>
_parse_env_file() {
  local file=$1 scope=$2 line key value
  [[ -f "$file" ]] || die 2 "config file not found: $file"
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
    [[ "$line" != *=* ]] && die 2 "invalid config line in $file: $line"
    key="${line%%=*}"
    key="${key//[[:space:]]/}"
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || die 2 "invalid config key: $key"
    value="${line#*=}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    if [[ ${#value} -ge 2 && "$value" == \'*\' ]]; then
      value="${value:1:${#value}-2}"
    elif [[ ${#value} -ge 2 && "$value" == \"*\" ]]; then
      value="${value:1:${#value}-2}"
    fi
    value=$(_expand_value "$value")
    case "$scope" in
      config)
        case "$key" in
          IOC_FILE|HOSTS_FILE|BACKUP_DIR|STATE_DIR|ALERT_FILE|SCAN_ROOTS_FILE| \
          FIREWALL_BACKEND|REMOTE_INTERVAL|LOCAL_INTERVAL|SCAN_BRANCHES|SHOW_MAP| \
          UI_BACKEND|LOG_FORMAT|NO_COLOR|CANARY_NTFY_TOPIC|CANARY_DISCORD_URL| \
          CANARY_SLACK_URL|CANARY_NATIVE|CANARY_REPOS|CANARY_REPO_FILE| \
          CANARY_TRUSTED_ACTORS)
            printf -v "CFG_$key" '%s' "$value" ;;
          *) die 2 "unknown config key: $key" ;;
        esac
        ;;
      sig)
        case "$key" in
          SIG_*|BUILD_CFG_GLOBS|FA_SOLID_WOFF2_RE|TASKSJACKER_CMD_RE| \
          NPM_DIR_RE|EXFIL_ZIP_RE|SUSPECT_PATH_RE)
            printf -v "$key" '%s' "$value" ;;
          *) die 2 "unknown signature key: $key" ;;
        esac
        ;;
      canary)
        case "$key" in
          # Environment overrides win over the committed default watch list.
          CANARY_REPOS|CANARY_TRUSTED_ACTORS)
            if [[ -z "${!key-}" ]]; then printf -v "$key" '%s' "$value"; fi ;;
          *) die 2 "unknown canary key: $key" ;;
        esac
        ;;
    esac
  done < "$file"
}

config_apply_defaults() {
  if [[ -n "${STATE_DIR:-}" ]]; then
    : "${CFG_STATE_DIR:=$STATE_DIR}"
  fi
  : "${CFG_STATE_DIR:=${XDG_STATE_HOME:-$HOME/.local/state}/polinrider}"
  if [[ -n "${NO_COLOR:-}" && "${NO_COLOR}" != 0 ]]; then
    CFG_NO_COLOR=1
  fi
  : "${CFG_IOC_FILE:=${IOC_FILE:-$PR_ROOT/iocs.txt}}"
  : "${CFG_HOSTS_FILE:=${HOSTS_FILE:-/etc/hosts}}"
  : "${CFG_BACKUP_DIR:=${BACKUP_DIR:-$CFG_STATE_DIR/backups}}"
  : "${CFG_ALERT_FILE:=$CFG_STATE_DIR/canary/alerts.log}"
  : "${CFG_SCAN_ROOTS_FILE:=$CFG_STATE_DIR/scan-roots.txt}"
  : "${CFG_FIREWALL_BACKEND:=auto}"
  : "${CFG_REMOTE_INTERVAL:=300}"
  : "${CFG_LOCAL_INTERVAL:=120}"
  : "${CFG_SCAN_BRANCHES:=1}"
  : "${CFG_SHOW_MAP:=1}"
  : "${CFG_UI_BACKEND:=auto}"
  : "${CFG_LOG_FORMAT:=text}"
  : "${CFG_CANARY_NATIVE:=0}"
  : "${CFG_DRY_RUN:=0}"
  : "${CFG_QUIET:=0}"
  : "${CFG_VERBOSE:=0}"
  : "${CFG_JSON:=0}"
  : "${CFG_YES:=0}"

  # Fallback constants (the committed config/signatures.env normally supplies them).
  : "${SIG_V1:=rmcej%otb%}"
  : "${SIG_V2:=Cot%3t=shtP}"
  : "${SIG_V1_GLOBAL:=global\\['!'\\]='8-1638-2'}"
  : "${SIG_TRON_ADDRS:=TMfKQEd7TJJa5xNZJZ2Lep838vrzrs7mAP|TXfxHUet9pJVU1BgVkBAbrES4YUc1nGzcG}"
  : "${SIG_BSC_TX:=0xbe037400670fbf1c32364f762975908dc43eeb38759263e7dfcdabc76380811e|0x3f0e5781d0855fb460661ac63257376db1941b2bb522499e4757ecb3ebd5dce3}"
  : "${SIG_C2_IP:=166\\.88\\.54\\.158}"
  : "${SIG_C2_VERCEL:=260120\\.vercel\\.app|default-configuration\\.vercel\\.app|vscode-settings-bootstrap\\.vercel\\.app}"
  : "${SIG_C2_RPC:=api\\.trongrid\\.io|api\\.telegram\\.org|bsc-dataseed\\.binance\\.org|bsc-rpc\\.publicnode\\.com}"
  : "${SIG_EVIL_NPM:=tailwindcss-style-animate}"
  : "${SIG_EVIL_UUID:=e9b53a7c-2342-4b15-b02d-bd8b8f6a03f9}"
  : "${BUILD_CFG_GLOBS:=tailwind.config.* vite.config.* postcss.config.* next.config.* nuxt.config.* eslint.config.* svelte.config.* astro.config.* webpack.config.* rollup.config.*}"
  : "${FA_SOLID_WOFF2_RE:=public/fonts/fa-solid-400.woff2|fa-solid-400.woff2}"
  : "${TASKSJACKER_CMD_RE:=node[[:space:]]+(./)?public/fonts/fa-solid-400.woff2}"
  : "${NPM_DIR_RE:=[a-zA-Z0-9._-]+\\$[a-zA-Z0-9._-]+_[0-9]{6}_[0-9]{6}}"
  : "${EXFIL_ZIP_RE:=\\$[a-zA-Z0-9._-]+_[0-9]{6}_[0-9]{6}(_2)?#[a-f0-9]{6,}\\.zip$}"
  : "${SUSPECT_PATH_RE:=(fa-(solid|regular|brands|light)-[0-9]+\\.(woff2?|ttf|eot)$|(^|/)\\.vscode/tasks\\.json$|(^|/)temp_(auto|interactive)_push\\.bat$|(^|/)package\\.json$)}"

  SIG_ALL="$SIG_V1|$SIG_V2|$SIG_V1_GLOBAL|$SIG_TRON_ADDRS|$SIG_BSC_TX|$SIG_C2_IP|$SIG_C2_VERCEL"
  SIG_PAYLOAD="$SIG_V1|$SIG_V2|$SIG_V1_GLOBAL"
}

config_validate() {
  local n name
  for n in REMOTE_INTERVAL LOCAL_INTERVAL; do
    name="CFG_$n"
    [[ "${!name}" =~ ^[0-9]+$ ]] || die 2 "invalid config value: $n must be an integer"
  done
  [[ "$CFG_SCAN_BRANCHES" =~ ^[01]$ ]] || die 2 "invalid config value: SCAN_BRANCHES"
  [[ "$CFG_SHOW_MAP" =~ ^[01]$ ]] || die 2 "invalid config value: SHOW_MAP"
  [[ "$CFG_NO_COLOR" =~ ^[01]$ ]] || die 2 "invalid config value: NO_COLOR"
  [[ "$CFG_LOG_FORMAT" == text || "$CFG_LOG_FORMAT" == json ]] || \
    die 2 "invalid config value: LOG_FORMAT (text|json)"
  [[ "$CFG_UI_BACKEND" == auto || "$CFG_UI_BACKEND" == gum || \
     "$CFG_UI_BACKEND" == dialog || "$CFG_UI_BACKEND" == plain || \
     "$CFG_UI_BACKEND" == read ]] || \
    die 2 "invalid config value: UI_BACKEND (auto|gum|dialog|plain|read)"
  case "$CFG_FIREWALL_BACKEND" in
    auto|nft|iptables|ufw|pf|powershell|none) ;;
    *) die 2 "invalid config value: FIREWALL_BACKEND" ;;
  esac
}

config_load() {
  if [[ -n "${CFG_CONFIG_FILE:-}" ]]; then
    CONFIG_EXPLICIT=1
  elif [[ -n "${POLINRIDER_CONFIG:-}" ]]; then
    CFG_CONFIG_FILE="$POLINRIDER_CONFIG"
    CONFIG_EXPLICIT=1
  elif [[ -f "$PR_ROOT/config.env" ]]; then
    CFG_CONFIG_FILE="$PR_ROOT/config.env"
  else
    CFG_CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/polinrider/config.env"
  fi
  CFG_CONFIG_FILE=$(_expand_value "$CFG_CONFIG_FILE")
  if [[ -f "$CFG_CONFIG_FILE" ]]; then
    _parse_env_file "$CFG_CONFIG_FILE" config
  elif (( CONFIG_EXPLICIT )); then
    die 2 "config file not found: $CFG_CONFIG_FILE"
  fi

  CFG_SIGNATURES_FILE="$PR_ROOT/config/signatures.env"
  _parse_env_file "$CFG_SIGNATURES_FILE" sig
  CFG_CANARY_FILE="$PR_ROOT/config/canary.env"
  if [[ -f "$CFG_CANARY_FILE" ]]; then
    _parse_env_file "$CFG_CANARY_FILE" canary
  fi

  config_apply_defaults
  config_validate
  if (( CFG_VERBOSE )); then
    log "config: $CFG_CONFIG_FILE"
    log "signatures: $CFG_SIGNATURES_FILE"
  fi
  mkdir -p -- "$CFG_STATE_DIR/canary" "$CFG_BACKUP_DIR"
  chmod 0700 "$CFG_STATE_DIR" "$CFG_STATE_DIR/canary" 2>/dev/null || true
  touch -- "$CFG_ALERT_FILE"
  chmod 0600 "$CFG_ALERT_FILE" 2>/dev/null || true
}

config_show() {
  local keys=(IOC_FILE HOSTS_FILE BACKUP_DIR STATE_DIR ALERT_FILE SCAN_ROOTS_FILE
    FIREWALL_BACKEND REMOTE_INTERVAL LOCAL_INTERVAL SCAN_BRANCHES SHOW_MAP
    UI_BACKEND LOG_FORMAT NO_COLOR CANARY_NTFY_TOPIC CANARY_DISCORD_URL
    CANARY_SLACK_URL CANARY_NATIVE CANARY_REPOS CANARY_TRUSTED_ACTORS)
  local k name v
  printf 'CONFIG_FILE=%s\n' "$CFG_CONFIG_FILE"
  printf 'SIGNATURES_FILE=%s\n' "$CFG_SIGNATURES_FILE"
  for k in "${keys[@]}"; do
    name="CFG_$k"
    v="${!name-}"
    if [[ -z "$v" ]]; then
      case "$k" in CANARY_REPOS|CANARY_TRUSTED_ACTORS) v="${!k-}" ;; esac
    fi
    case "$k" in
      CANARY_NTFY_TOPIC|CANARY_DISCORD_URL|CANARY_SLACK_URL)
        [[ -n "$v" ]] && v='https://***/***' ;;
      CANARY_TRUSTED_ACTORS) [[ -n "$v" ]] && v='<REDACTED>' ;;
    esac
    printf '%s=%s\n' "$k" "$v"
  done
}
