#!/usr/bin/env bash
set -euo pipefail

# Simple installer to wire sremain.sh, scrime.sh and smine.sh to convenient commands
# via ~/.bashrc and optional wrappers in ~/.local/bin.

RC_FILE="${HOME}/.bashrc"
MARK_BEGIN="# >>> sremain alias >>>"
MARK_END="# <<< sremain alias <<<"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--rc PATH] [--path PATH] [--scrime-path PATH] [--smine-path PATH] [--uninstall] [--no-wrapper]

Options:
  --rc PATH      Target rc file (default: ~/.bashrc)
  --path PATH    Absolute path to sremain.sh to embed in alias
  --scrime-path  Absolute path to scrime.sh to embed in alias
  --smine-path   Absolute path to smine.sh to embed in alias
  --uninstall    Remove the sremain alias block and wrapper
  --no-wrapper   Do not create ~/.local/bin/sremain wrapper

This adds function aliases to call the repo's scripts as `sremain`, `scrime` and `smine`.
After installing, run: source "\$RC_FILE" or open a new shell.
EOF
}

UNINSTALL=0
NO_WRAPPER=0
SREMAIN_PATH=""
SCRIME_PATH=""
SMINE_PATH=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --rc) shift; RC_FILE="${1:-}"; [[ -n "$RC_FILE" ]] || { echo "--rc requires a path" >&2; exit 1; }; shift ;;
    --path) shift; SREMAIN_PATH="${1:-}"; [[ -n "$SREMAIN_PATH" ]] || { echo "--path requires a path" >&2; exit 1; }; shift ;;
    --scrime-path) shift; SCRIME_PATH="${1:-}"; [[ -n "$SCRIME_PATH" ]] || { echo "--scrime-path requires a path" >&2; exit 1; }; shift ;;
    --smine-path) shift; SMINE_PATH="${1:-}"; [[ -n "$SMINE_PATH" ]] || { echo "--smine-path requires a path" >&2; exit 1; }; shift ;;
    --uninstall) UNINSTALL=1; shift ;;
    --no-wrapper) NO_WRAPPER=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
[[ -z "$SREMAIN_PATH" ]] && SREMAIN_PATH="${REPO_DIR}/sremain.sh"
[[ -z "$SCRIME_PATH" ]] && SCRIME_PATH="${REPO_DIR}/scrime.sh"
[[ -z "$SMINE_PATH" ]] && SMINE_PATH="${REPO_DIR}/smine.sh"

if [[ ! -x "$SREMAIN_PATH" && -e "$SREMAIN_PATH" ]]; then
  echo "Making sremain.sh executable" >&2
  chmod +x "$SREMAIN_PATH"
fi
if [[ ! -x "$SCRIME_PATH" && -e "$SCRIME_PATH" ]]; then
  echo "Making scrime.sh executable" >&2
  chmod +x "$SCRIME_PATH"
fi
if [[ ! -x "$SMINE_PATH" && -e "$SMINE_PATH" ]]; then
  echo "Making smine.sh executable" >&2
  chmod +x "$SMINE_PATH"
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
  WRAP_PATH2="${WRAP_DIR}/scrime"
  if [[ -e "$WRAP_PATH2" ]]; then
    rm -f "$WRAP_PATH2"
    echo "Removed wrapper: $WRAP_PATH2"
  fi
  WRAP_PATH3="${WRAP_DIR}/smine"
  if [[ -e "$WRAP_PATH3" ]]; then
    rm -f "$WRAP_PATH3"
    echo "Removed wrapper: $WRAP_PATH3"
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
scrime() {
  "${SCRIME_PATH}" "\$@"
}
smine() {
  "${SMINE_PATH}" "\$@"
}
${MARK_END}
BLOCK

echo "Installed sremain/scrime/smine aliases into ${RC_FILE}"
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

  WRAP_PATH2="${WRAP_DIR}/scrime"
  cat > "$WRAP_PATH2" <<WRAP
#!/usr/bin/env bash
exec "${SCRIME_PATH}" "\$@"
WRAP
  chmod +x "$WRAP_PATH2"
  echo "Installed wrapper: $WRAP_PATH2"

  WRAP_PATH3="${WRAP_DIR}/smine"
  cat > "$WRAP_PATH3" <<WRAP
#!/usr/bin/env bash
exec "${SMINE_PATH}" "\$@"
WRAP
  chmod +x "$WRAP_PATH3"
  echo "Installed wrapper: $WRAP_PATH3"
  # Ensure ~/.local/bin in PATH suggestion
  case ":$PATH:" in
    *":$WRAP_DIR:"*) : ;; # already present
    *) echo "Note: Add ${WRAP_DIR} to your PATH to use 'sremain'/'scrime'/'smine' globally." ;;
  esac
fi

echo "Done. Test with: sremain --help | scrime --help | smine --help"
