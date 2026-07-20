#!/usr/bin/env bash
# plymouth boot splash setup — review before running, needs root.
# backs up grub config, mkinitcpio.conf and the current initramfs first;
# every edit is guarded so rerunning is safe.
set -euo pipefail

[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
command -v plymouth-set-default-theme >/dev/null || { echo "install plymouth first: pacman -S plymouth"; exit 1; }

here="$(cd "$(dirname "$0")" && pwd)"
ts="$(date +%Y%m%d-%H%M%S)"

# grub is optional — on systemd-boot/rEFInd you put `splash` on the kernel line
# yourself, so only touch grub when it's actually the bootloader here
grub_cfg=""
if [ -f /etc/default/grub ] && command -v grub-mkconfig >/dev/null; then
    grub_cfg=/boot/grub/grub.cfg
    for c in /boot/grub/grub.cfg /boot/grub2/grub.cfg /efi/grub/grub.cfg /boot/efi/grub/grub.cfg; do
        if [ -f "$c" ]; then grub_cfg="$c"; break; fi
    done
    cp -a /etc/default/grub "/etc/default/grub.bak-$ts"
fi

cp -a /etc/mkinitcpio.conf "/etc/mkinitcpio.conf.bak-$ts"
# every kernel's initramfs, not just `linux` — lts/zen boxes have their own
for img in /boot/initramfs-*.img; do
    case "$img" in *'*'*|*fallback*) continue ;; esac
    cp -a "$img" "$img.bak-$ts"
done
echo "backups stamped .bak-$ts"

mkdir -p /usr/share/plymouth/themes/world80
cp "$here"/themes/world80/* /usr/share/plymouth/themes/world80/

if [ -n "$grub_cfg" ]; then
    sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' /etc/default/grub
    sed -i 's/^GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=hidden/' /etc/default/grub
    grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=.*splash' /etc/default/grub || \
        sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 splash"/' /etc/default/grub
else
    echo "no grub here — add 'splash' and hide the menu on your bootloader's kernel line by hand"
fi

# plymouth goes after whichever hook brings the console up: systemd on a
# systemd-initrd box, udev on stock Arch
if ! grep -q '^HOOKS=.*plymouth' /etc/mkinitcpio.conf; then
    if grep -qE '^HOOKS=.*\bsystemd\b' /etc/mkinitcpio.conf; then
        sed -i -E '/^HOOKS=/ s/\bsystemd\b/systemd plymouth/' /etc/mkinitcpio.conf
    elif grep -qE '^HOOKS=.*\budev\b' /etc/mkinitcpio.conf; then
        sed -i -E '/^HOOKS=/ s/\budev\b/udev plymouth/' /etc/mkinitcpio.conf
    fi
fi
grep -q '^HOOKS=.*plymouth' /etc/mkinitcpio.conf || { echo "HOOKS has neither systemd nor udev — add plymouth by hand, aborting before regen"; exit 1; }

plymouth-set-default-theme world80
mkinitcpio -P
if [ -n "$grub_cfg" ]; then
    grub-mkconfig -o "$grub_cfg"
    # grub-mkconfig bakes "echo 'Loading Linux...'" lines into the entries and has
    # no knob for it — strip them so the hidden boot stays silent
    sed -i "/echo[[:space:]]*'Loading/d" "$grub_cfg"
fi

echo
echo "== result =="
if [ -n "$grub_cfg" ]; then grep -E '^(GRUB_TIMEOUT|GRUB_TIMEOUT_STYLE|GRUB_CMDLINE_LINUX_DEFAULT)' /etc/default/grub; fi
grep '^HOOKS' /etc/mkinitcpio.conf
echo "theme: $(plymouth-set-default-theme)"
echo
echo "rescue notes:"
echo "  - hold ESC during boot for the grub menu"
echo "  - add plymouth.enable=0 to the kernel line to skip the splash"
echo "  - restore the .bak-$ts files, then: mkinitcpio -P${grub_cfg:+ && grub-mkconfig -o $grub_cfg}"
