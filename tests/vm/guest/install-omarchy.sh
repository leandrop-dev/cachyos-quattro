#!/bin/bash
# Runs on the guest from ~/cq: install Omarchy with cachyos-quattro, unattended, the way every
# scenario that starts from an installed system needs it.

set -euo pipefail

# mirror5.krfoss.org and mirror.krfoss.org head the golden images' CachyOS mirror lists and
# answered HTTP 503 for some .sig files on 2026-10-21, failing whole transactions; re-ranking
# kept them first. Drop them so the scenarios test cachyos-quattro, not one mirror.
sudo sed -i '/krfoss\.org/d' /etc/pacman.d/cachyos-mirrorlist /etc/pacman.d/cachyos-v3-mirrorlist /etc/pacman.d/cachyos-v4-mirrorlist

# omarchy-update-stay-awake runs `sudo -v`, which asks for a password unless every sudoers rule
# matching the user is NOPASSWD (verifypw=all) and the stock %wheel rule is not. A real user has
# the timestamp `sudo true` cached at the start of update; the NOPASSWD test user never does.
echo "Defaults:tester verifypw=any" | sudo tee /etc/sudoers.d/11-tester-verifypw >/dev/null

CQ_USER_NAME="CQ Tester" CQ_USER_EMAIL="tester@example.invalid" ./bin/cachyos-quattro install --yes
