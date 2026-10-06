#!/usr/bin/env bash
# Call ~/.liveform/bin/liveform. If missing, download the matching release quietly.
set +e
LIVEFORM_BIN="${HOME}/.liveform/bin/liveform"
REPO_OWNER="stewymccarthy"
REPO_NAME="liveform-plugin"

ensure_liveform() {
  if [ -x "$LIVEFORM_BIN" ]; then
    return 0
  fi

  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  arch="$(uname -m)"
  case "$os" in
    darwin|linux) ;;
    *) return 1 ;;
  esac
  case "$arch" in
    x86_64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    *) return 1 ;;
  esac

  asset="liveform-${os}-${arch}"
  screen_asset="screen-${os}-${arch}"
  base="https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/latest/download"
  tmp="$(mktemp -d 2>/dev/null)" || return 1
  # shellcheck disable=SC2064
  trap "rm -rf \"$tmp\"" EXIT

  if ! command -v curl >/dev/null 2>&1; then
    return 1
  fi
  curl -fsSL "$base/$asset" -o "$tmp/$asset" || return 1
  curl -fsSL "$base/checksums.txt" -o "$tmp/checksums.txt" || return 1
  curl -fsSL "$base/$screen_asset" -o "$tmp/$screen_asset" || return 1

  if command -v sha256sum >/dev/null 2>&1; then
    got="$(sha256sum "$tmp/$asset" | awk '{print $1}')"
    screen_got="$(sha256sum "$tmp/$screen_asset" | awk '{print $1}')"
  elif command -v shasum >/dev/null 2>&1; then
    got="$(shasum -a 256 "$tmp/$asset" | awk '{print $1}')"
    screen_got="$(shasum -a 256 "$tmp/$screen_asset" | awk '{print $1}')"
  else
    return 1
  fi

  want="$(awk -v f="$asset" 'NF>=2 && $NF==f {print $1; exit}' "$tmp/checksums.txt")"
  screen_want="$(awk -v f="$screen_asset" 'NF>=2 && $NF==f {print $1; exit}' "$tmp/checksums.txt")"
  if [ -z "$want" ] || [ -z "$screen_want" ]; then
    return 1
  fi
  if [ "$(printf '%s' "$got" | tr '[:upper:]' '[:lower:]')" != "$(printf '%s' "$want" | tr '[:upper:]' '[:lower:]')" ]; then
    return 1
  fi
  if [ "$(printf '%s' "$screen_got" | tr '[:upper:]' '[:lower:]')" != "$(printf '%s' "$screen_want" | tr '[:upper:]' '[:lower:]')" ]; then
    return 1
  fi

  mkdir -p "${HOME}/.liveform/bin" || return 1
  mv "$tmp/$asset" "$LIVEFORM_BIN" || return 1
  chmod a+x "$LIVEFORM_BIN" || return 1
  mv "$tmp/$screen_asset" "${HOME}/.liveform/bin/$screen_asset" || return 1
  chmod a+x "${HOME}/.liveform/bin/$screen_asset" || return 1
  return 0
}

if ! ensure_liveform; then
  printf '%s\n' '{}'
  exit 0
fi

"$LIVEFORM_BIN" "$@"
exit $?
