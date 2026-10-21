# Task: qt612-bridge
Status: done
Deps: 10

## Goal
Pin `import QtQuick 6.11` in the Omarchy shell while omarchy is older than 4.5.0 and qt6-declarative is 6.12 or newer, so shell surfaces keep their colours until upstream's fix ships.

## Steps
1. Reproduce first, on an overlay of `limine-plain` after `cachyos-quattro install` (task 10): log in to the Omarchy session, open the launcher and lock the screen, and capture each with QMP `screendump` into `tests/vm/run/`. Record whether surfaces render black. If they do not, stop: record the result in state.md and close this task without code.
2. On the same overlay, run `sudo sed -i -E 's/^import QtQuick$/import QtQuick 6.11/' ` over `/usr/share/omarchy/shell/**/*.qml`, restart the shell (`omarchy-restart-shell`, confirm the name in `ledger/commands.4.0.6.tsv`), and capture the same screens. Proceed only if the colours are back.
3. Write `package/libexec/qt-bridge`: exits 0 doing nothing unless `vercmp "$(pacman -Q omarchy | cut -d' ' -f2)" 4.5.0` is negative and `vercmp "$(pacman -Q qt6-declarative | cut -d' ' -f2)" 6.12` is not negative; otherwise rewrites exactly the line `import QtQuick` to `import QtQuick 6.11` in every `${CQ_ROOT}/usr/share/omarchy/shell/**/*.qml`, logs the file count to `${CQ_ROOT}/var/log/cachyos-quattro.log`, and leaves files with any other `import QtQuick` form untouched.
4. Write `package/hooks/50-cachyos-quattro-qt-bridge.hook`: `Operation = Install, Upgrade`, `Type = Package`, `Target = omarchy`, `Target = omarchy-dev`, `Target = qt6-declarative`; `When = PostTransaction`; `Exec = /usr/lib/cachyos-quattro/qt-bridge`. Add both files to `package/PKGBUILD`.
5. Add a `qt-bridge` line to `package/libexec/verify` as `warn` (never FAIL): reports when the pin is active, and when it is active although omarchy ≥ 4.5.0 (should not happen). Update `cmd_status` to explain that `pacman -Qkk omarchy` lists the pinned shell files as modified.
6. Write `tests/unit/qt-bridge.bats` with a fixture shell tree and stubbed `pacman`/`vercmp`: pins on omarchy 4.0.6 + Qt 6.12.0; does nothing on Qt 6.11.1; does nothing on omarchy 4.5.0; leaves `import QtQuick 2.15` and `import QtQuick.Controls` lines alone; is idempotent.
7. Add `tests/vm/scenarios/shell-ui.sh` screens to task 13 for both images, with and without the bridge.

## TDD Checklist
- [ ] Write failing test
- [ ] Confirm test fails (red)
- [ ] Implement
- [ ] Confirm test passes (green)
- [ ] Confirm no regressions

## Notes
Root cause, from juliankgp's README (line 25) and upstream #14553: Qt 6.12 adds a `QtQuick.Color` type that shadows the shell's `qs.Commons` `Color` singleton. A versioned import hides types added after that version. Upstream's fix (`b83d3df0`, in v4.5.0-rc1) qualifies every reference as `Commons.Color`; once omarchy 4.5.0 is installed its files replace the pinned ones and the bridge stops. The bridge edits files the `omarchy` package owns; that is the accepted cost (state.md, 2026-10-21).

Result (2026-10-21): closed at step 1 without code; Omarchy 4.0.6 is not affected.
- Reproduction on a kept `limine-luks` overlay after `cachyos-quattro install` (`qt6-declarative 6.12.0-1.1`, `quickshell 0.3.2-1.1`, `omarchy 4.0.6-1`): QMP screendumps of the desktop, the Omarchy menu (`omarchy-menu summon`) and the lock screen (`omarchy-system-lock`) all show Tokyo Night colours; the user journal has 0 shell lines matching `undefined|QColor|TypeError|ReferenceError`.
- Why: Qt 6.12.0 does register `QtQuick/Color 6.12` (`/usr/lib/qt6/qml/QtQuick/plugins.qmltypes`), but #14553 was cherry-picked into the 4.0.x line as `bfac6650` (2026-10-08) and shipped in v4.0.5: files using `Commons.Color` go from 2 in v4.0.4 to 54 in v4.0.5 and v4.0.6 (`git grep -l`), and the packaged 4.0.6 shell has the same 54. The planning-time blocker rested on `b83d3df0` not being an ancestor of `v4.0.6`, which misses cherry-picks.
- Upstream's other Qt 6.12 change, `51717f10` ("Patch all QtQuick imports to 6.11 to work around plugin Color bug", 4.5 only), adds a load pragma to `shell.qml` for plugin loading; 4.0.6 renders correctly without it. Recheck when 4.5.0 is reviewed (task 12 diff).
