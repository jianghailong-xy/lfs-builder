#!/usr/bin/env bash
# LFS 13.0-systemd Chapter 9 and section 10.2. Run as root in the LFS chroot.
set -euo pipefail

part="$(findmnt -n -o SOURCE /)"
case "$part" in /dev/loop[0-9]*p1) ;; *) echo "unexpected root source: $part" >&2; exit 1 ;; esac
partuuid="$(blkid -s PARTUUID -o value "$part")"
[ -n "$partuuid" ] || { echo "PARTUUID not found for $part" >&2; exit 1; }

install -d -m 0755 /etc/systemd/network /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/network/10-dhcp.network <<'EOF'
[Match]
Name=en* eth*

[Network]
DHCP=ipv4

[DHCPv4]
UseDomains=true
EOF

printf 'lfs\n' > /etc/hostname
cat > /etc/hosts <<'EOF'
127.0.0.1 localhost
127.0.1.1 lfs
::1       localhost ip6-localhost ip6-loopback
ff02::1   ip6-allnodes
ff02::2   ip6-allrouters
EOF

ln -snf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
cat > /etc/vconsole.conf <<'EOF'
KEYMAP=us
FONT=Lat2-Terminus16
EOF
printf 'LANG=en_US.UTF-8\n' > /etc/locale.conf
cat > /etc/profile <<'EOF'
# Begin /etc/profile
for i in $(locale); do
  unset ${i%=*}
done
if [[ "$TERM" = linux ]]; then
  export LANG=C.UTF-8
else
  export LANG=en_US.UTF-8
fi
# End /etc/profile
EOF
cat > /etc/inputrc <<'EOF'
# Begin /etc/inputrc
set horizontal-scroll-mode Off
set meta-flag On
set input-meta On
set convert-meta Off
set output-meta On
set bell-style none
"\eOd": backward-word
"\eOc": forward-word
# End /etc/inputrc
EOF
cat > /etc/shells <<'EOF'
/bin/sh
/bin/bash
EOF
cat > /etc/systemd/system/getty@tty1.service.d/noclear.conf <<'EOF'
[Service]
TTYVTDisallocate=no
EOF

# systemd creates this target on first boot; keep the canonical resolver link.
ln -snf ../run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
systemctl enable systemd-networkd.service systemd-resolved.service systemd-timesyncd.service

# chroot.sh prep recreates the Chapter 7 test account; Chapter 8 cleanup requires
# it to be absent in the finished system.
if id tester >/dev/null 2>&1; then userdel -r tester || true; fi

cat > /etc/fstab <<EOF
# Begin /etc/fstab
PARTUUID=$partuuid  /  ext4  defaults  1  1
# End /etc/fstab
EOF

bash -n /etc/profile
findmnt --verify --tab-file /etc/fstab
grep -qx "PARTUUID=$partuuid  /  ext4  defaults  1  1" /etc/fstab
printf 'Chapter 9 and section 10.2 configured with PARTUUID=%s\n' "$partuuid"
