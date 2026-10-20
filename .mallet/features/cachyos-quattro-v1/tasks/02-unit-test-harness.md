# Task: unit-test-harness
Status: done
Deps: 01

## Goal
Add bats and shellcheck test tooling with a Makefile and a CI workflow.

## Steps
1. Install tools locally: `sudo pacman -S --needed bats shellcheck` (Arch package `extra/bats`).
2. Create `Makefile` with targets:
   - `lint`: `shellcheck -x -S style bin/* lib/*.sh package/libexec/* package/stubs/* tools/*`
   - `test`: `bats -r tests/unit`
   - `check`: `lint test`
3. Create `tests/unit/helpers.bash` exporting `CQ_ROOT="$BATS_TEST_TMPDIR/root"` and a `mkroot` function that copies `tests/fixtures/<name>/` into `$CQ_ROOT`.
4. Create `tests/fixtures/cachyos-limine-luks/` with `etc/os-release` (ID=cachyos), `etc/mkinitcpio.conf` (HOOKS with systemd, sd-encrypt, sd-btrfs-overlayfs), `etc/default/limine`, `etc/pacman.conf`, `etc/pacman.d/mirrorlist`, `etc/nsswitch.conf` copied from a CachyOS install, and `proc/cmdline` containing `rd.luks.uuid=`. Create `tests/fixtures/cachyos-limine-plain/` the same without LUKS.
5. Create `tests/unit/smoke.bats` asserting `mkroot cachyos-limine-luks` produces `$CQ_ROOT/etc/os-release` with `ID=cachyos`.
6. Create `.github/workflows/ci.yml`: on push and pull_request, `runs-on: ubuntu-latest`, container `archlinux:latest`, steps `pacman -Syu --noconfirm --needed bats shellcheck make git`, `make check`.
7. Run `make check` locally; it passes.

## TDD Checklist
- [ ] Write failing test (`smoke.bats` before fixtures exist)
- [ ] Confirm test fails (red)
- [ ] Implement fixtures and helpers
- [ ] Confirm test passes (green)
- [ ] Confirm no regressions

## Notes
Fixture files come from a real CachyOS install (the golden VM from task 03 or this dev machine); strip machine-specific UUIDs to placeholders.
