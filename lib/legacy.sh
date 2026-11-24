# lib/legacy.sh — shared helper for the legacy shell wrappers.
# Keeps wrappers thin: no scanning/blocking logic lives outside bin/polinrider.

legacy_exec() {
  local root=$1 action=$2
  shift 2
  exec "$root/bin/polinrider" "$action" "$@"
}
