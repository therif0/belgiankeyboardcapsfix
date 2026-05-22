#!/usr/bin/env bash
# azerty-caps-fix uninstaller.
#
# Restores /usr/share/X11/xkb/symbols/be from the backup written by
# install.sh and asks kwin to reload its keyboard config.
#
# Requires root; the script re-execs itself under sudo if needed.

set -euo pipefail

XKB_FILE=/usr/share/X11/xkb/symbols/be
BACKUP="${XKB_FILE}.azerty-caps-fix.orig"

RULES_XML=/usr/share/X11/xkb/rules/evdev.xml
RULES_LST=/usr/share/X11/xkb/rules/evdev.lst
RULES_XML_BACKUP="${RULES_XML}.azerty-caps-fix.orig"
RULES_LST_BACKUP="${RULES_LST}.azerty-caps-fix.orig"

# Old user-path artefacts from the pre-v1 implementation, removed if found.
LEGACY_PATHS=(
    "${HOME}/.local/bin/azerty-caps-fix"
    "${HOME}/.config/systemd/user/azerty-caps-fix.service"
    "${HOME}/.config/xkb/keymaps/azerty-caps-fix.xkb"
    "${HOME}/.config/xkb/symbols/azerty-caps-fix"
)

# ---------------------------------------------------------------------------
# Clean up the legacy user-scope files *before* escalating, so HOME still
# points at the real user.
# ---------------------------------------------------------------------------
if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    if command -v systemctl >/dev/null 2>&1; then
        systemctl --user disable --now azerty-caps-fix.service 2>/dev/null || true
        systemctl --user daemon-reload 2>/dev/null || true
    fi
    for p in "${LEGACY_PATHS[@]}"; do
        [[ -e "$p" ]] && rm -f -- "$p"
    done

    if ! command -v sudo >/dev/null 2>&1; then
        echo "uninstall.sh: must be run as root (no 'sudo' on PATH)." >&2
        exit 1
    fi
    exec sudo -- bash "$0" "$@"
fi

# ---------------------------------------------------------------------------
# Restore the system XKB file from backup.
# ---------------------------------------------------------------------------
if [[ ! -f "$BACKUP" ]]; then
    if grep -q 'azerty-caps-fix' "$XKB_FILE" 2>/dev/null; then
        cat >&2 <<EOF
uninstall.sh: $XKB_FILE is patched but $BACKUP is missing.
I won't risk corrupting your keymap. Reinstall xkeyboard-config to get a
clean copy, then re-run this script:

    sudo dnf reinstall xkeyboard-config     # Fedora
    sudo apt --reinstall install xkb-data    # Debian/Ubuntu
    sudo pacman -S xkeyboard-config          # Arch

EOF
        exit 1
    fi
    echo "nothing to uninstall — $XKB_FILE is not patched and no backup exists."
    exit 0
fi

# 'cp -a' to keep the inode (hardlink to xkeyboard-config-2 mirror).
cp -a "$BACKUP" "$XKB_FILE"
rm -f -- "$BACKUP"

# Restore the KDE-visible rules files too.
for pair in "${RULES_XML_BACKUP}:${RULES_XML}" "${RULES_LST_BACKUP}:${RULES_LST}"; do
    src="${pair%%:*}"
    dst="${pair##*:}"
    if [[ -f "$src" ]]; then
        cp -a "$src" "$dst"
        rm -f -- "$src"
    elif grep -q 'azerty-caps-fix' "$dst" 2>/dev/null; then
        echo "warning: $dst has azerty-caps-fix marks but no backup ($src) — leaving as-is." >&2
    fi
done

echo "azerty-caps-fix uninstalled. Please log out and back in."
