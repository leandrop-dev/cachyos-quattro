# Test fixtures

Each directory is a fake root that `mkroot` (in `tests/unit/helpers.bash`) copies into
`$CQ_ROOT` for one test:

| Fixture | Source image | Install |
|---|---|---|
| `cachyos-limine-plain` | `limine-plain` | CachyOS ISO 260809, No Desktop, btrfs, Limine, no encryption |
| `cachyos-limine-luks` | `limine-luks` | Same, with *Encrypt system* (LUKS root unlocked by `sd-encrypt`) |

Every file was copied from the golden VM images (see `docs/testing.md`) with
`tests/vm/fetch.sh`. The only edits: each UUID, machine ID and file hash is replaced
by zeros. The files are what the CachyOS installer and packages wrote, so a test reads
the same HOOKS, `/etc/default/limine`, `limine.conf`, cmdline, snapper and pacman
configuration as a real install.

`etc/mkinitcpio.conf.d/10-chwd-qemu.conf` comes from CachyOS's hardware detection
(chwd) on a QEMU guest. On real hardware it has a different name and modules, e.g. NVIDIA.

To refresh after re-creating the golden images:

```bash
tests/vm/fetch.sh limine-plain build/golden/limine-plain <paths...>
```

Then repeat the zeroing for UUIDs (`8-4-4-4-12` hex), 32-character machine IDs,
128-character `b2sum` hashes and `_sha256_<64 hex>` history names.
