#!/usr/bin/env bash
# azerty-caps-fix installer.
#
# Patches /usr/share/X11/xkb/symbols/be so the be(oss) variant locks the
# digits row when Caps Lock is on. See KDE-WAYLAND-INVESTIGATION.md for
# the full rationale.
#
# Requires root; the script re-execs itself under sudo if needed.
# Idempotent: re-running on an already-patched file is a no-op.
# No systemd service is installed — the system XKB file is read by
# kwin/libxkbcommon on every login, so persistence is automatic.
# Basics laid by therif0 (Myself) and vibecoded notes/inline documentation
# and repetitive work

set -euo pipefail

XKB_FILE=/usr/share/X11/xkb/symbols/be
VARIANT=oss
BACKUP="${XKB_FILE}.azerty-caps-fix.orig"

# KDE System Settings → Keyboard reads variant *descriptions* from these
# two rules files, NOT from name[Group1] in the symbols file. We patch
# them so the Layouts list visibly reflects that the keymap is modified.
RULES_XML=/usr/share/X11/xkb/rules/evdev.xml
RULES_LST=/usr/share/X11/xkb/rules/evdev.lst
RULES_XML_BACKUP="${RULES_XML}.azerty-caps-fix.orig"
RULES_LST_BACKUP="${RULES_LST}.azerty-caps-fix.orig"

ORIG_DESC='Belgian (alt.)'
NEW_DESC='Belgian (alt.) — digit-lock Caps'

# ---------------------------------------------------------------------------
# Escalate to root if needed.
# ---------------------------------------------------------------------------
if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    if ! command -v sudo >/dev/null 2>&1; then
        echo "install.sh: must be run as root (no 'sudo' on PATH)." >&2
        exit 1
    fi
    # Preserve SUDO_USER so the reload step below can find the user's bus.
    exec sudo -- bash "$0" "$@"
fi

# ---------------------------------------------------------------------------
# Sanity checks.
# ---------------------------------------------------------------------------
if [[ ! -f "$XKB_FILE" ]]; then
    echo "install.sh: $XKB_FILE not found. Is xkeyboard-config installed?" >&2
    exit 1
fi

if grep -q 'azerty-caps-fix' "$XKB_FILE"; then
    echo "$XKB_FILE is already patched — nothing to do."
    echo "(Run ./uninstall.sh first if you want to refresh the patch.)"
    exit 0
fi

# ---------------------------------------------------------------------------
# Back up the original.
#
# Use 'cp -a' (open + O_TRUNC + write) rather than 'install' or 'mv', so the
# inode is preserved and the hardlink to /usr/share/xkeyboard-config-2/symbols/be
# stays intact. xkeyboard-config ships this file as a hardlink pair; breaking
# it confuses some libxkbcommon code paths.
# ---------------------------------------------------------------------------
cp -a "$XKB_FILE" "$BACKUP"

# ---------------------------------------------------------------------------
# Patch in-place via a brace-aware Python helper (sed cannot match nested
# braces; the variant block contains many '{ ... };' key definitions).
# ---------------------------------------------------------------------------
python3 - "$XKB_FILE" "$VARIANT" <<'PYEOF'
import re
import sys

path, variant = sys.argv[1], sys.argv[2]
with open(path, "r", encoding="utf-8") as f:
    text = f.read()

if "azerty-caps-fix" in text:
    # Belt-and-braces; the shell already checked this.
    sys.exit(0)

header = re.search(
    r'xkb_symbols\s+"' + re.escape(variant) + r'"\s*\{',
    text,
)
if not header:
    print(f'install.sh: could not find xkb_symbols "{variant}" in {path}',
          file=sys.stderr)
    sys.exit(2)

# Find the matching closing brace of the variant body.
body_start = header.end()
depth = 1
i = body_start
n = len(text)
while i < n and depth > 0:
    c = text[i]
    if c == "{":
        depth += 1
    elif c == "}":
        depth -= 1
        if depth == 0:
            close_idx = i
            break
    i += 1
else:
    print("install.sh: unbalanced braces in target block", file=sys.stderr)
    sys.exit(2)

# This block is the verbatim content documented in §3 of
# KDE-WAYLAND-INVESTIGATION.md. Keep them in sync.
patch = """
    // ===== azerty-caps-fix: digits-row Caps Lock — begin =====
    // Sets FOUR_LEVEL_LOCKABLE_LEVEL2 on every non-letter key with a
    // base/shifted pair. NoSymbol entries augment-merge over the included
    // base layout, so the included symbols are preserved; only the key
    // type changes.
    key.type[group1] = "FOUR_LEVEL_LOCKABLE_LEVEL2";
    key <TLDE> { [ NoSymbol, NoSymbol, NoSymbol, NoSymbol ] };
    key <AE01> { [ NoSymbol, NoSymbol, NoSymbol, NoSymbol ] };
    key <AE02> { [ NoSymbol, NoSymbol, NoSymbol, NoSymbol ] };
    key <AE03> { [ NoSymbol, NoSymbol, NoSymbol, NoSymbol ] };
    key <AE04> { [ NoSymbol, NoSymbol, NoSymbol, NoSymbol ] };
    key <AE05> { [ NoSymbol, NoSymbol, NoSymbol, NoSymbol ] };
    key <AE06> { [ NoSymbol, NoSymbol, NoSymbol, NoSymbol ] };
    key <AE07> { [ NoSymbol, NoSymbol, NoSymbol, NoSymbol ] };
    key <AE08> { [ NoSymbol, NoSymbol, NoSymbol, NoSymbol ] };
    key <AE09> { [ NoSymbol, NoSymbol, NoSymbol, NoSymbol ] };
    key <AE10> { [ NoSymbol, NoSymbol, NoSymbol, NoSymbol ] };
    key <AE11> { [ NoSymbol, NoSymbol, NoSymbol, NoSymbol ] };
    key <AE12> { [ NoSymbol, NoSymbol, NoSymbol, NoSymbol ] };
    key <AD11> { [ NoSymbol, NoSymbol, NoSymbol, NoSymbol ] };
    key <AD12> { [ NoSymbol, NoSymbol, NoSymbol, NoSymbol ] };
    key <AC11> { [ NoSymbol, NoSymbol, NoSymbol, NoSymbol ] };
    key <BKSL> { [ NoSymbol, NoSymbol, NoSymbol, NoSymbol ] };
    key <AB07> { [ NoSymbol, NoSymbol, NoSymbol, NoSymbol ] };
    key <AB08> { [ NoSymbol, NoSymbol, NoSymbol, NoSymbol ] };
    key <AB09> { [ NoSymbol, NoSymbol, NoSymbol, NoSymbol ] };
    key <AB10> { [ NoSymbol, NoSymbol, NoSymbol, NoSymbol ] };
    key <LSGT> { [ NoSymbol, NoSymbol, NoSymbol, NoSymbol ] };

    // CAPS toggles BOTH Lock (so letters capitalize and the LED lights)
    // AND LevelFive (so the LOCKABLE_LEVEL2 keys above flip to their
    // Shift layer). The upstream caps:digits_row_independent_lock option
    // compiles to a CAPS keymap that can't reach LevelFive — see §4.
    override key <CAPS> {
        type[Group1] = "ONE_LEVEL",
        symbols[Group1] = [ ISO_Level5_Lock ],
        actions[Group1] = [ LockMods(modifiers = Lock + LevelFive) ]
    };
    // ===== azerty-caps-fix: digits-row Caps Lock — end =======
"""

# Also update name[Group1] inside this block so KDE System Settings →
# Keyboard shows that the layout has been modified. Stays a no-op if the
# block has no name line.
body = text[body_start:close_idx]
new_body = re.sub(
    r'(name\[Group1\]\s*=\s*")([^"]*)(")',
    lambda m: m.group(1) + m.group(2) + " — digit-lock Caps" + m.group(3),
    body,
    count=1,
)

new_text = text[:body_start] + new_body + patch + text[close_idx:]

with open(path, "w", encoding="utf-8") as f:
    f.write(new_text)
PYEOF

# ---------------------------------------------------------------------------
# Patch evdev.xml and evdev.lst so KDE System Settings → Keyboard
# displays the modified description in the Layouts list.
# ---------------------------------------------------------------------------
if [[ -f "$RULES_XML" ]] && ! grep -q 'azerty-caps-fix' "$RULES_XML"; then
    cp -a "$RULES_XML" "$RULES_XML_BACKUP"
    python3 - "$RULES_XML" "$ORIG_DESC" "$NEW_DESC" <<'PYEOF'
import re, sys
path, orig, new = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path, "r", encoding="utf-8") as f:
    text = f.read()

# Match <name>oss</name> immediately followed by <description>Belgian (alt.)</description>.
# Variant names are unique within a layout but not across layouts (French
# also has 'oss'), so anchoring on the original description disambiguates.
pattern = re.compile(
    r'(<name>oss</name>\s*<description>)' + re.escape(orig) + r'(</description>)',
)
new_text, n = pattern.subn(r'\1' + new + r'\2 <!-- azerty-caps-fix -->', text)
if n != 1:
    print(f"install.sh: expected 1 match in {path}, got {n}", file=sys.stderr)
    sys.exit(2)
with open(path, "w", encoding="utf-8") as f:
    f.write(new_text)
PYEOF
fi

if [[ -f "$RULES_LST" ]] && ! grep -q 'azerty-caps-fix' "$RULES_LST"; then
    cp -a "$RULES_LST" "$RULES_LST_BACKUP"
    python3 - "$RULES_LST" "$ORIG_DESC" "$NEW_DESC" <<'PYEOF'
import re, sys
path, orig, new = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path, "r", encoding="utf-8") as f:
    text = f.read()
# Line format:  "  oss             be: Belgian (alt.)"
pattern = re.compile(
    r'^(\s*oss\s+be:\s*)' + re.escape(orig) + r'(\s*)$',
    re.MULTILINE,
)
new_text, n = pattern.subn(r'\1' + new + r'  # azerty-caps-fix\2', text)
if n != 1:
    print(f"install.sh: expected 1 match in {path}, got {n}", file=sys.stderr)
    sys.exit(2)
with open(path, "w", encoding="utf-8") as f:
    f.write(new_text)
PYEOF
fi

echo "azerty-caps-fix installed. Please log out and back in."
