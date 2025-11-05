#!/usr/bin/env bash
set -euo pipefail

# Simple installer to wire sremain.sh to the `sremain` command via ~/.bashrc

RC_FILE="${HOME}/.bashrc"
MARK_BEGIN="# >>> sremain alias >>>"
MARK_END="# <<< sremain alias <<<"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--rc PATH] [--uninstall]

Options:
  --rc PATH      Target rc file (default: ~/.bashrc)
  --uninstall    Remove the sremain alias block from the rc file

This adds a function alias to call the repo's sremain.sh as `sremain`.
After installing, run: source "\$RC_FILE"
EOF
}

UNINSTALL=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --rc) shift; RC_FILE="${1:-}"; [[ -n "$RC_FILE" ]] || { echo "--rc requires a path" >&2; exit 1; }; shift ;;
    --uninstall) UNINSTALL=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
SREMAIN_PATH="${REPO_DIR}/sremain.sh"

if [[ ! -x "$SREMAIN_PATH" ]]; then
  echo "Making sremain.sh executable" >&2
  chmod +x "$SREMAIN_PATH"
fi

mkdir -p "$(dirname "$RC_FILE")"
touch "$RC_FILE"

remove_block() {
  # Remove installed block if present
  if grep -q "^${MARK_BEGIN}$" "$RC_FILE" 2>/dev/null; then
    tmp="${RC_FILE}.tmp.$$"
    awk "BEGIN{keep=1} \n /^${MARK_BEGIN//\//\/}$/ {keep=0; next} \n /^${MARK_END//\//\/}$/ {keep=1; next} \n {if(keep) print}" "$RC_FILE" > "$tmp"
    mv "$tmp" "$RC_FILE"
  fi
}

if (( UNINSTALL )); then
  remove_block
  echo "Removed sremain alias block from ${RC_FILE}"
  exit 0
fi

# Install (replace if exists)
remove_block

cat >> "$RC_FILE" <<BLOCK
${MARK_BEGIN}
# Added by cluster-remains/install.sh
sremain() {
  "${SREMAIN_PATH}" "${@}"
}
${MARK_END}
BLOCK

echo "Installed sremain alias into ${RC_FILE}"
echo "Run: source ${RC_FILE}  (or open a new shell)"

