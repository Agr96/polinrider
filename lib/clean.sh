# lib/clean.sh — stage-only removal of PolinRider repo artifacts. Never commits.

clean_vscode() {
  local root=$1
  if [[ -e "$root/.vscode" ]]; then
    run_cmd git -C "$root" rm -r --quiet -- .vscode || return 1
    ok 'staged deletion: .vscode/'
    return 0
  fi
  return 1
}

clean_fonts() {
  local root=$1
  if [[ -e "$root/public/fonts" ]]; then
    run_cmd git -C "$root" rm -r --quiet -- public/fonts || return 1
    ok 'staged deletion: public/fonts/'
    return 0
  fi
  return 1
}

clean_gitignore() {
  local root=$1 gi="$1/.gitignore" tmp="$CLEANUP_DIR/gitignore" changed=1
  if [[ -f "$gi" ]]; then
    awk '
      /temp_(auto|interactive)_push\.bat/ { next }
      /^[[:space:]]*\.gitignore[[:space:]]*$/ { next }
      { print }
    ' "$gi" > "$tmp"
  else
    : > "$tmp"
  fi
  grep -qF '*.polinrider-bak' "$tmp" || printf '*.polinrider-bak\n' >> "$tmp"
  if [[ -f "$gi" ]] && cmp -s "$gi" "$tmp"; then
    changed=0
  else
    write_file "$gi" "$tmp" || return 1
    run_cmd git -C "$root" add -- .gitignore || return 1
  fi
  (( changed )) && ok 'staged cleanup: .gitignore'
  return 0
}

clean_config_payload() {
  local root=$1 glob f bak mid tmp final changed=0 oldifs=$IFS
  local -a files=() globs=()
  IFS=' '
  read -r -a globs <<< "$BUILD_CFG_GLOBS"
  IFS=$oldifs
  for glob in "${globs[@]}"; do
    while IFS= read -r -d '' f; do
      files+=("$f")
    done < <(find "$root" -maxdepth 4 -type f -name "$glob" \
      -not -path '*/node_modules/*' -not -path '*/.git/*' -print0 2>/dev/null || true)
  done
  for f in "${files[@]}"; do
    grep -qE "$SIG_PAYLOAD" "$f" 2>/dev/null || continue
    bak="$f.polinrider-bak"
    mid="$CLEANUP_DIR/cfg.mid"
    final="$CLEANUP_DIR/cfg.final"
    run_cmd cp -p "$f" "$bak" || return 1
    if (( ! CFG_DRY_RUN )); then chmod 0600 "$bak"; fi
    awk '/^[[:space:]]*global\[/ { exit } { print }' "$f" > "$mid"
    awk '
      /createRequire/ && /module/ { next }
      { print }
    ' "$mid" > "$final"
    write_file "$f" "$final" || return 1
    run_cmd git -C "$root" add -- "$f" || return 1
    ok "staged payload strip: ${f#$root/} (backup: ${bak#$root/})"
    changed=1
  done
  (( changed )) && return 0
  return 1
}

clean_all() {
  local root=$1 changed=0
  [[ -d "$root/.git" ]] || die 2 "Not a git repo: $root"
  log "PolinRider repo cleanup in $(cd "$root" && pwd) (git rm only; no node/VS Code execution)"

  if clean_vscode "$root"; then changed=1; fi
  if clean_fonts "$root"; then changed=1; fi
  clean_gitignore "$root" || return 1
  if clean_config_payload "$root"; then changed=1; fi

  if (( changed )); then
    ok 'Staged. Review with: git status && git diff --cached'
    warn 'Do NOT open this repo in VS Code until merged.'
  else
    ok 'Nothing to remove — repository is clean.'
  fi
  return 0
}
