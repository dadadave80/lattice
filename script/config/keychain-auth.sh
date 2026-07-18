#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# keychain-auth.sh — run a command with FORGE_AUTH materialized from the macOS
# Keychain, so unattended runs never park a keystore password in a lasting file.
#
#   keychain-auth.sh <keystore-name> <command> [args...]
#
# Looks up the Keychain item 'foundry-<keystore-name>', writes the password to
# a 0600 temp file, runs <command> with FORGE_AUTH="--account <keystore-name>
# --password-file <tmpfile>", and deletes the file on exit (also on Ctrl-C).
#
# One-time setup per keystore (prompts; nothing lands in shell history):
#   security add-generic-password -a "$USER" -s foundry-<keystore-name> -w
#
# macOS-only (uses the `security` CLI). Elsewhere, pass FORGE_AUTH yourself.
# ---------------------------------------------------------------------------
set -euo pipefail

[[ $# -ge 2 ]] || { echo "usage: $(basename "$0") <keystore-name> <command> [args...]" >&2; exit 2; }
KS="$1"; shift

# Downstream demo scripts expand ${FORGE_AUTH} UNQUOTED by design (it word-splits into flags), so no
# component may contain whitespace: reject such keystore names, and keep the password file on a
# whitespace-free path (fall back to /tmp when TMPDIR has spaces — the file itself is 0600 either way).
[[ "${KS}" == *[[:space:]]* ]] && { echo "keychain-auth: keystore name must not contain whitespace." >&2; exit 2; }
TMP_BASE="${TMPDIR:-/tmp}"
[[ "${TMP_BASE}" == *[[:space:]]* ]] && TMP_BASE="/tmp"

command -v security >/dev/null 2>&1 \
    || { echo "keychain-auth: 'security' CLI not found (macOS-only helper) — pass FORGE_AUTH yourself." >&2; exit 2; }

umask 077
# The XXXXXX must be TRAILING: macOS/BSD mktemp does not randomize a mid-template X block, silently
# using the literal name instead (a predictable, collision-prone path for a secret).
PW_FILE="$(mktemp "${TMP_BASE}/${KS}.pw.XXXXXX")"
trap 'rm -f "${PW_FILE}"' EXIT INT TERM

# Lookup by service (-s) only — no `-a "${USER}"`: launchd/cron (the unattended contexts this exists
# for) often run without USER set, which under `set -u` turns into a confusing unbound-variable error.
# tr strips the trailing newline some foundry versions reject in a password file.
security find-generic-password -s "foundry-${KS}" -w 2>/dev/null | tr -d '\n' > "${PW_FILE}" || true
[[ -s "${PW_FILE}" ]] || {
    echo "keychain-auth: no (or empty) Keychain item 'foundry-${KS}'. One-time setup:" >&2
    echo "  security add-generic-password -a \"\$USER\" -s foundry-${KS} -w" >&2
    exit 2
}

FORGE_AUTH="--account ${KS} --password-file ${PW_FILE}" "$@"
