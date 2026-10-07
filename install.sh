#!/bin/sh
# Install Liveform for Claude Code and Cursor.
# Usage: curl -fsSL https://raw.githubusercontent.com/stewymccarthy/liveform-plugin/main/install.sh | sh
#        sh install.sh --uninstall
set -eu

REPO_OWNER="stewymccarthy"
REPO_NAME="liveform-plugin"
MARKETPLACE_SRC="${REPO_OWNER}/${REPO_NAME}"
MARKETPLACE_NAME="liveform"
PLUGIN_SPEC="liveform@liveform"
RELEASE_BASE="${LIVEFORM_RELEASE_BASE:-https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/latest/download}"

CREATED_LIVEFORM_HOME=0
MODE="install"

log() {
  printf '%s\n' "$*"
}

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

expand_home() {
  case "$1" in
    "~/"*) printf '%s/%s\n' "$HOME" "${1#~/}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

LIVEFORM_HOME="$(expand_home "${LIVEFORM_HOME:-$HOME/.liveform}")"
BIN_DIR="$LIVEFORM_HOME/bin"
LIVEFORM_BIN="$BIN_DIR/liveform"
CURSOR_HOOKS="$(expand_home "${CURSOR_HOOKS:-$HOME/.cursor/hooks.json}")"
CURSOR_DIR="$(dirname "$CURSOR_HOOKS")"

# Clearly marked block in shell profiles; install once, uninstall removes only this.
LIVEFORM_PATH_BEGIN="# >>> Liveform >>>"
LIVEFORM_PATH_END="# <<< Liveform <<<"

path_block_bash_zsh() {
  printf '%s\n' \
    "$LIVEFORM_PATH_BEGIN" \
    "export PATH=\"${BIN_DIR}:\$PATH\"" \
    "$LIVEFORM_PATH_END"
}

path_block_fish() {
  printf '%s\n' \
    "$LIVEFORM_PATH_BEGIN" \
    "set -gx PATH ${BIN_DIR} \$PATH" \
    "$LIVEFORM_PATH_END"
}

# Append the Liveform PATH block once. Never touches project folders.
ensure_path_in_profile() {
  profile="$1"
  kind="$2"
  dir="$(dirname "$profile")"
  mkdir -p "$dir"
  if [ -f "$profile" ] && grep -qF "$LIVEFORM_PATH_BEGIN" "$profile" 2>/dev/null; then
    return 0
  fi
  if [ -f "$profile" ] && [ -s "$profile" ]; then
    printf '\n' >>"$profile"
  fi
  case "$kind" in
    fish) path_block_fish >>"$profile" ;;
    *) path_block_bash_zsh >>"$profile" ;;
  esac
}

# Remove only the marked Liveform block; leave every other line unchanged.
remove_path_from_profile() {
  profile="$1"
  if [ ! -f "$profile" ]; then
    return 0
  fi
  if ! grep -qF "$LIVEFORM_PATH_BEGIN" "$profile" 2>/dev/null; then
    return 0
  fi
  tmp="$(mktemp)"
  awk -v begin="$LIVEFORM_PATH_BEGIN" -v end="$LIVEFORM_PATH_END" '
    $0 == begin { skip=1; next }
    $0 == end { skip=0; next }
    skip { next }
    { print }
  ' "$profile" >"$tmp"
  mv "$tmp" "$profile"
}

profile_has_liveform_path() {
  [ -f "$1" ] && grep -qF "$LIVEFORM_PATH_BEGIN" "$1" 2>/dev/null
}

install_shell_path() {
  already=0
  if profile_has_liveform_path "$HOME/.zshrc" \
    && profile_has_liveform_path "$HOME/.bashrc" \
    && profile_has_liveform_path "$HOME/.config/fish/config.fish"; then
    already=1
  fi
  ensure_path_in_profile "$HOME/.zshrc" zsh
  ensure_path_in_profile "$HOME/.bashrc" bash
  ensure_path_in_profile "$HOME/.config/fish/config.fish" fish
  if [ "$already" -eq 1 ]; then
    log "PATH already includes $BIN_DIR."
  else
    log "Added $BIN_DIR to your PATH (zsh, bash, fish)."
    log "Open a new terminal so the liveform command works."
  fi
}

uninstall_shell_path() {
  remove_path_from_profile "$HOME/.zshrc"
  remove_path_from_profile "$HOME/.bashrc"
  remove_path_from_profile "$HOME/.config/fish/config.fish"
  log "Removed Liveform PATH block from shell profiles."
}

detect_platform() {
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  arch="$(uname -m)"
  case "$os" in
    darwin|linux) ;;
    *)
      die "Liveform supports macOS and Linux only (found: $(uname -s))."
      ;;
  esac
  case "$arch" in
    x86_64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    *)
      die "Liveform supports amd64 and arm64 processors only (found: $(uname -m))."
      ;;
  esac
  OS="$os"
  ARCH="$arch"
  ASSET="liveform-${OS}-${ARCH}"
  SCREEN_ASSET="screen-${OS}-${ARCH}"
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    die "Need sha256sum or shasum to verify the download."
  fi
}

checksum_for() {
  asset="$1"
  file="$2"
  awk -v f="$asset" 'NF>=2 && $NF==f {print $1; exit}' "$file"
}

download_release() {
  detect_platform
  if [ ! -d "$LIVEFORM_HOME" ]; then
    mkdir -p "$LIVEFORM_HOME"
    CREATED_LIVEFORM_HOME=1
  fi
  mkdir -p "$BIN_DIR"

  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap 'rm -rf "$tmp"' EXIT

  if ! command -v curl >/dev/null 2>&1; then
    die "Need curl to download Liveform."
  fi

  curl -fsSL "$RELEASE_BASE/$ASSET" -o "$tmp/$ASSET" || die "Could not download $ASSET."
  curl -fsSL "$RELEASE_BASE/checksums.txt" -o "$tmp/checksums.txt" || die "Could not download checksums.txt."
  curl -fsSL "$RELEASE_BASE/$SCREEN_ASSET" -o "$tmp/$SCREEN_ASSET" || die "Could not download $SCREEN_ASSET."

  want="$(checksum_for "$ASSET" "$tmp/checksums.txt")"
  screen_want="$(checksum_for "$SCREEN_ASSET" "$tmp/checksums.txt")"
  if [ -z "$want" ] || [ -z "$screen_want" ]; then
    cleanup_failed_download
    die "checksums.txt is missing an entry for this machine."
  fi
  got="$(sha256_file "$tmp/$ASSET")"
  screen_got="$(sha256_file "$tmp/$SCREEN_ASSET")"
  if [ "$(printf '%s' "$got" | tr '[:upper:]' '[:lower:]')" != "$(printf '%s' "$want" | tr '[:upper:]' '[:lower:]')" ]; then
    cleanup_failed_download
    die "Checksum mismatch for $ASSET. Install stopped; nothing was changed."
  fi
  if [ "$(printf '%s' "$screen_got" | tr '[:upper:]' '[:lower:]')" != "$(printf '%s' "$screen_want" | tr '[:upper:]' '[:lower:]')" ]; then
    cleanup_failed_download
    die "Checksum mismatch for $SCREEN_ASSET. Install stopped; nothing was changed."
  fi

  same=0
  if [ -x "$LIVEFORM_BIN" ]; then
    existing="$(sha256_file "$LIVEFORM_BIN")"
    if [ "$(printf '%s' "$existing" | tr '[:upper:]' '[:lower:]')" = "$(printf '%s' "$got" | tr '[:upper:]' '[:lower:]')" ]; then
      same=1
    fi
  fi

  if [ "$same" -eq 0 ]; then
    mv "$tmp/$ASSET" "$LIVEFORM_BIN"
    chmod a+x "$LIVEFORM_BIN"
    log "Installed program to $LIVEFORM_BIN"
  else
    log "Program already up to date at $LIVEFORM_BIN"
  fi

  screen_dest="$BIN_DIR/$SCREEN_ASSET"
  screen_same=0
  if [ -x "$screen_dest" ]; then
    existing_screen="$(sha256_file "$screen_dest")"
    if [ "$(printf '%s' "$existing_screen" | tr '[:upper:]' '[:lower:]')" = "$(printf '%s' "$screen_got" | tr '[:upper:]' '[:lower:]')" ]; then
      screen_same=1
    fi
  fi
  if [ "$screen_same" -eq 0 ]; then
    mv "$tmp/$SCREEN_ASSET" "$screen_dest"
    chmod a+x "$screen_dest"
    log "Installed privacy screen to $screen_dest"
  fi

  rm -rf "$tmp"
  trap - EXIT
}

cleanup_failed_download() {
  rm -rf "${tmp:-}"
  if [ ! -x "$LIVEFORM_BIN" ]; then
    rm -f "$LIVEFORM_BIN" 2>/dev/null || true
    rm -f "$BIN_DIR/$SCREEN_ASSET" 2>/dev/null || true
  fi
  if [ "$CREATED_LIVEFORM_HOME" -eq 1 ]; then
    # Leave credentials/config alone; only remove an empty new home we created.
    if [ -d "$BIN_DIR" ] && [ -z "$(ls -A "$BIN_DIR" 2>/dev/null || true)" ]; then
      rmdir "$BIN_DIR" 2>/dev/null || true
    fi
    if [ -d "$LIVEFORM_HOME" ] && [ -z "$(ls -A "$LIVEFORM_HOME" 2>/dev/null || true)" ]; then
      rmdir "$LIVEFORM_HOME" 2>/dev/null || true
    fi
  fi
}

is_liveform_command() {
  cmd="$1"
  printf '%s' "$cmd" | grep -Eqi \
    '(\.liveform/bin/|/liveform[[:space:]]+hook|liveform-(darwin|linux)-(amd64|arm64)|plugins/liveform/|LiveformV2/plugin/|liveform-plugin/|/cursor/hooks/(session-start|prompt|edit|stop)\.sh|/hooks/(session-start|prompt|edit|stop)\.sh)'
}

install_cursor_hooks() {
  if [ ! -d "$(expand_home "$HOME/.cursor")" ] && [ ! -e "$CURSOR_HOOKS" ]; then
    return 0
  fi
  if [ ! -d "$(expand_home "$HOME/.cursor")" ]; then
    return 0
  fi

  if ! command -v python3 >/dev/null 2>&1; then
    die "Need python3 to update ~/.cursor/hooks.json."
  fi

  mkdir -p "$CURSOR_DIR"
  export LIVEFORM_BIN CURSOR_HOOKS
  python3 <<'PY'
import json, os, re, shutil, sys

path = os.environ["CURSOR_HOOKS"]
liveform_bin = os.environ["LIVEFORM_BIN"]
wanted = {
    "sessionStart": f'"{liveform_bin}" hook session-start --tool cursor',
    "beforeSubmitPrompt": f'"{liveform_bin}" hook prompt --tool cursor',
    "afterFileEdit": f'"{liveform_bin}" hook edit --tool cursor',
    "stop": f'"{liveform_bin}" hook stop --tool cursor',
}
pattern = re.compile(
    r"(\.liveform/bin/|/liveform\s+hook|liveform-(darwin|linux)-(amd64|arm64)|"
    r"plugins/liveform/|LiveformV2/plugin/|liveform-plugin/|"
    r"/cursor/hooks/(session-start|prompt|edit|stop)\.sh|"
    r"/hooks/(session-start|prompt|edit|stop)\.sh)",
    re.I,
)

def is_liveform(cmd: str) -> bool:
    return bool(pattern.search(cmd or ""))

if os.path.exists(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            raw = f.read()
        doc = json.loads(raw)
    except json.JSONDecodeError:
        print(f"{path} is not valid JSON. Fix or remove it, then run install again.", file=sys.stderr)
        sys.exit(1)
    except OSError as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)
else:
    doc = {"version": 1, "hooks": {}}
    raw = None

if not isinstance(doc, dict):
    print(f"{path} is not valid JSON. Fix or remove it, then run install again.", file=sys.stderr)
    sys.exit(1)

hooks = doc.get("hooks")
if hooks is None:
    hooks = {}
    doc["hooks"] = hooks
if not isinstance(hooks, dict):
    print(f"{path} is not valid JSON. Fix or remove it, then run install again.", file=sys.stderr)
    sys.exit(1)

if "version" not in doc:
    doc["version"] = 1

changed = False
for event, command in wanted.items():
    entries = hooks.get(event)
    if entries is None:
        entries = []
    if not isinstance(entries, list):
        print(f"{path} is not valid JSON. Fix or remove it, then run install again.", file=sys.stderr)
        sys.exit(1)
    kept = []
    found_exact = False
    for entry in entries:
        if not isinstance(entry, dict):
            kept.append(entry)
            continue
        cmd = entry.get("command", "")
        if cmd == command:
            found_exact = True
            kept.append(entry)
            continue
        if is_liveform(str(cmd)):
            changed = True
            continue
        kept.append(entry)
    if not found_exact:
        kept.append({"command": command})
        changed = True
    hooks[event] = kept

# Also strip Liveform entries from any other hook events.
for event, entries in list(hooks.items()):
    if event in wanted or not isinstance(entries, list):
        continue
    new_entries = []
    for entry in entries:
        if isinstance(entry, dict) and is_liveform(str(entry.get("command", ""))):
            changed = True
            continue
        new_entries.append(entry)
    hooks[event] = new_entries

if raw is not None and not changed:
    print(f"Cursor hooks already configured in {path}")
    sys.exit(0)

backup = path + ".bak"
if os.path.exists(path):
    shutil.copy2(path, backup)
    print(f"Backed up Cursor hooks to {backup}")

with open(path, "w", encoding="utf-8") as f:
    json.dump(doc, f, indent=2)
    f.write("\n")
print(f"Configured Cursor hooks in {path}")
PY
}

# True only for plugin name exactly "liveform" (any marketplace), e.g. liveform@liveform-local.
is_liveform_plugin_spec() {
  case "$1" in
    liveform@*[!A-Za-z0-9._-]*) return 1 ;;
    liveform@[A-Za-z0-9._-]*) return 0 ;;
    *) return 1 ;;
  esac
}

# True only for marketplaces named exactly liveform or liveform-local.
is_liveform_marketplace_name() {
  case "$1" in
    liveform|liveform-local) return 0 ;;
    *) return 1 ;;
  esac
}

claude_plugin_specs() {
  # Prints specs whose plugin name is exactly liveform (any marketplace).
  claude plugin list 2>/dev/null | awk '
    {
      for (i = 1; i <= NF; i++) {
        tok = $i
        gsub(/[,;].*$/, "", tok)
        gsub(/^[^A-Za-z0-9@._-]+/, "", tok)
        gsub(/[^A-Za-z0-9@._-]+$/, "", tok)
        if (tok ~ /^liveform@[A-Za-z0-9._-]+$/) print tok
      }
    }
  ' | sort -u
}

claude_marketplace_names() {
  # Prints only exact marketplace names liveform or liveform-local when present.
  claude plugin marketplace list 2>/dev/null | awk '
    {
      for (i = 1; i <= NF; i++) {
        tok = $i
        gsub(/[,:;].*$/, "", tok)
        gsub(/^[^A-Za-z0-9._-]+/, "", tok)
        gsub(/[^A-Za-z0-9._-]+$/, "", tok)
        if (tok == "liveform" || tok == "liveform-local") print tok
      }
    }
  ' | sort -u
}

remove_liveform_plugin_spec() {
  spec="$1"
  if ! is_liveform_plugin_spec "$spec"; then
    return 0
  fi
  claude plugin uninstall "$spec" >/dev/null 2>&1 || true
  log "Removed Claude plugin $spec"
}

remove_liveform_marketplace() {
  market="$1"
  if ! is_liveform_marketplace_name "$market"; then
    return 0
  fi
  claude plugin marketplace remove "$market" >/dev/null 2>&1 || true
  log "Removed Claude marketplace $market"
}

install_claude() {
  if ! command -v claude >/dev/null 2>&1; then
    log "Claude Code not found; skipped plugin install"
    return 0
  fi

  # Remove any liveform plugin from another marketplace (exact name only).
  specs="$(claude_plugin_specs || true)"
  for spec in $specs; do
    case "$spec" in
      "$PLUGIN_SPEC") ;;
      *)
        remove_liveform_plugin_spec "$spec"
        ;;
    esac
  done

  # Remove liveform-local only; keep marketplace named exactly liveform.
  markets="$(claude_marketplace_names || true)"
  for market in $markets; do
    case "$market" in
      "$MARKETPLACE_NAME") ;;
      liveform-local)
        remove_liveform_marketplace "$market"
        ;;
    esac
  done

  if ! claude plugin marketplace list 2>/dev/null | grep -Eq "(^|[[:space:]])${MARKETPLACE_NAME}([[:space:]]|$)|${MARKETPLACE_SRC}"; then
    claude plugin marketplace add "$MARKETPLACE_SRC" >/dev/null 2>&1 || \
      claude plugin marketplace add "$MARKETPLACE_SRC" || die "Could not add Claude marketplace $MARKETPLACE_SRC"
    log "Added Claude marketplace $MARKETPLACE_SRC"
  else
    log "Claude marketplace $MARKETPLACE_NAME already present"
  fi

  if claude_plugin_specs | grep -Fxq "$PLUGIN_SPEC"; then
    log "Claude plugin $PLUGIN_SPEC already installed"
  else
    claude plugin install "$PLUGIN_SPEC" >/dev/null 2>&1 || \
      claude plugin install "$PLUGIN_SPEC" || die "Could not install $PLUGIN_SPEC"
    log "Installed Claude plugin $PLUGIN_SPEC"
  fi

  # Final guarantee: only liveform@liveform remains among liveform plugins.
  specs="$(claude_plugin_specs || true)"
  for spec in $specs; do
    case "$spec" in
      "$PLUGIN_SPEC") ;;
      *)
        remove_liveform_plugin_spec "$spec"
        ;;
    esac
  done
}

finish_signin() {
  if [ ! -x "$LIVEFORM_BIN" ]; then
    return 0
  fi
  if "$LIVEFORM_BIN" whoami >/dev/null 2>&1; then
    email="$("$LIVEFORM_BIN" whoami 2>/dev/null || true)"
    log "Signed in as ${email:-user}"
    return 0
  fi
  log "Not signed in; starting sign-in"
  "$LIVEFORM_BIN" signin || true
}

uninstall_cursor_hooks() {
  if [ ! -f "$CURSOR_HOOKS" ]; then
    log "No Cursor hooks file at $CURSOR_HOOKS"
    return 0
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    die "Need python3 to update ~/.cursor/hooks.json."
  fi
  export CURSOR_HOOKS
  python3 <<'PY'
import json, os, re, shutil, sys

path = os.environ["CURSOR_HOOKS"]
pattern = re.compile(
    r"(\.liveform/bin/|/liveform\s+hook|liveform-(darwin|linux)-(amd64|arm64)|"
    r"plugins/liveform/|LiveformV2/plugin/|liveform-plugin/|"
    r"/cursor/hooks/(session-start|prompt|edit|stop)\.sh|"
    r"/hooks/(session-start|prompt|edit|stop)\.sh)",
    re.I,
)

try:
    with open(path, "r", encoding="utf-8") as f:
        doc = json.load(f)
except json.JSONDecodeError:
    print(f"{path} is not valid JSON. Fix or remove it, then run uninstall again.", file=sys.stderr)
    sys.exit(1)

hooks = doc.get("hooks")
if not isinstance(hooks, dict):
    print(f"Removed Liveform hooks from {path}")
    sys.exit(0)

changed = False
for event, entries in list(hooks.items()):
    if not isinstance(entries, list):
        continue
    kept = []
    for entry in entries:
        if isinstance(entry, dict) and pattern.search(str(entry.get("command", ""))):
            changed = True
            continue
        kept.append(entry)
    hooks[event] = kept

if changed:
    backup = path + ".bak"
    shutil.copy2(path, backup)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(doc, f, indent=2)
        f.write("\n")
    print(f"Removed Liveform hooks from {path}")
else:
    print(f"No Liveform hooks in {path}")
PY
}

uninstall_claude() {
  if ! command -v claude >/dev/null 2>&1; then
    log "Claude Code not found; skipped plugin uninstall"
    return 0
  fi
  specs="$(claude_plugin_specs || true)"
  for spec in $specs; do
    if is_liveform_plugin_spec "$spec"; then
      claude plugin uninstall "$spec" >/dev/null 2>&1 || true
      log "Uninstalled Claude plugin $spec"
    fi
  done
  # Only exact Liveform marketplace names; never substring-match.
  markets="$(claude_marketplace_names || true)"
  markets="$markets
$MARKETPLACE_NAME
liveform-local"
  markets="$(printf '%s\n' "$markets" | sort -u)"
  for market in $markets; do
    [ -n "$market" ] || continue
    remove_liveform_marketplace "$market"
  done
}

uninstall_home() {
  if [ ! -d "$LIVEFORM_HOME" ]; then
    log "No $LIVEFORM_HOME to remove"
    return 0
  fi
  if [ ! -t 0 ]; then
    log "Kept $LIVEFORM_HOME (non-interactive; pass yes on stdin to delete)"
    return 0
  fi
  printf 'Delete %s (credentials and config)? [y/N] ' "$LIVEFORM_HOME"
  read -r answer || answer=""
  case "$answer" in
    y|Y|yes|YES)
      rm -rf "$LIVEFORM_HOME"
      log "Deleted $LIVEFORM_HOME"
      ;;
    *)
      log "Kept $LIVEFORM_HOME"
      ;;
  esac
}

do_uninstall() {
  uninstall_cursor_hooks
  uninstall_claude
  uninstall_shell_path
  uninstall_home
  log "Uninstall finished"
}

do_install() {
  download_release
  install_shell_path

  if command -v claude >/dev/null 2>&1; then
    install_claude
  else
    log "Claude Code not found; skipped plugin install"
  fi

  if [ -d "$(expand_home "$HOME/.cursor")" ]; then
    install_cursor_hooks
  else
    log "Cursor not found; skipped hooks install"
  fi

  finish_signin
}

for arg in "$@"; do
  case "$arg" in
    --uninstall) MODE="uninstall" ;;
    -h|--help)
      printf '%s\n' "Usage: sh install.sh [--uninstall]"
      exit 0
      ;;
  esac
done

if [ "$MODE" = "uninstall" ]; then
  do_uninstall
else
  do_install
fi
