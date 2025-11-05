#!/usr/bin/env bash
set -euo pipefail

# Simple installer to wire sremain.sh to the `sremain` command via ~/.bashrc
# and an optional wrapper in ~/.local/bin/sremain.

RC_FILE="${HOME}/.bashrc"
MARK_BEGIN="# >>> sremain alias >>>"
MARK_END="# <<< sremain alias <<<"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--rc PATH] [--path PATH] [--uninstall] [--no-wrapper]

Options:
  --rc PATH      Target rc file (default: ~/.bashrc)
  --path PATH    Absolute path to sremain.sh to embed in alias
  --uninstall    Remove the sremain alias block and wrapper
  --no-wrapper   Do not create ~/.local/bin/sremain wrapper

This adds a function alias to call the repo's sremain.sh as `sremain`.
After installing, run: source "\$RC_FILE" or open a new shell.
EOF
}

UNINSTALL=0
NO_WRAPPER=0
SREMAIN_PATH=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --rc) shift; RC_FILE="${1:-}"; [[ -n "$RC_FILE" ]] || { echo "--rc requires a path" >&2; exit 1; }; shift ;;
    --path) shift; SREMAIN_PATH="${1:-}"; [[ -n "$SREMAIN_PATH" ]] || { echo "--path requires a path" >&2; exit 1; }; shift ;;
    --uninstall) UNINSTALL=1; shift ;;
    --no-wrapper) NO_WRAPPER=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -z "$SREMAIN_PATH" ]]; then
  SREMAIN_PATH="${REPO_DIR}/sremain.sh"
fi

if [[ ! -x "$SREMAIN_PATH" && -e "$SREMAIN_PATH" ]]; then
  echo "Making sremain.sh executable" >&2
  chmod +x "$SREMAIN_PATH"
fi

mkdir -p "$(dirname "$RC_FILE")"
touch "$RC_FILE"

remove_block() {
  # Remove installed block if present (sed range delete)
  if grep -q "^${MARK_BEGIN}$" "$RC_FILE" 2>/dev/null; then
    tmp="${RC_FILE}.tmp.$$"
    local BEGIN_ESC END_ESC
    BEGIN_ESC=$(printf '%s' "$MARK_BEGIN" | sed 's/[\/&]/\\&/g')
    END_ESC=$(printf '%s' "$MARK_END" | sed 's/[\/&]/\\&/g')
    sed "/^${BEGIN_ESC}\$/,/^${END_ESC}\$/d" "$RC_FILE" > "$tmp"
    mv "$tmp" "$RC_FILE"
  fi
}

if (( UNINSTALL )); then
  remove_block
  WRAP_DIR="${HOME}/.local/bin"
  WRAP_PATH="${WRAP_DIR}/sremain"
  if [[ -e "$WRAP_PATH" ]]; then
    rm -f "$WRAP_PATH"
    echo "Removed wrapper: $WRAP_PATH"
  fi
  echo "Removed sremain alias block from ${RC_FILE}"
  exit 0
fi

# Install (replace if exists)
remove_block

cat >> "$RC_FILE" <<BLOCK
${MARK_BEGIN}
# Added by cluster-remains/install.sh
sremain() {
  "${SREMAIN_PATH}" "\$@"
}
${MARK_END}
BLOCK

echo "Installed sremain alias into ${RC_FILE}"
echo "Run: source ${RC_FILE}  (or open a new shell)"

# Create wrapper in ~/.local/bin for broader shell support
if (( NO_WRAPPER == 0 )); then
  WRAP_DIR="${HOME}/.local/bin"
  WRAP_PATH="${WRAP_DIR}/sremain"
  mkdir -p "$WRAP_DIR"
  cat > "$WRAP_PATH" <<WRAP
#!/usr/bin/env bash
exec "${SREMAIN_PATH}" "\$@"
WRAP
  chmod +x "$WRAP_PATH"
  echo "Installed wrapper: $WRAP_PATH"
  # Ensure ~/.local/bin in PATH suggestion
  case ":$PATH:" in
    *":$WRAP_DIR:"*) : ;; # already present
    *) echo "Note: Add ${WRAP_DIR} to your PATH to use 'sremain' globally." ;;
  esac
fi

echo "Done. Test with: sremain --help or sremain -a"
