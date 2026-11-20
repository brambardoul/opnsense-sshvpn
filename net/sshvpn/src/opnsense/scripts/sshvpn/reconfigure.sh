#!/bin/sh
# Copyright (c) 2026 Bram Bardoul
# SPDX-License-Identifier: BSD-2-Clause
#
# Apply SSH VPN settings to the core OpenSSH service:
#  1. render templates (sshd drop-in, client keys, tunnel list)
#  2. create/configure/remove tun/tap interfaces
#  3. restart core sshd only if the drop-in actually changed
#     (client key changes need no restart, sshd reads the keys file per login;
#      rc.sshd only kills the listener, established sessions survive)
#

DROPIN=/usr/local/etc/ssh/sshd_config.d/50-sshvpn.conf
KEYDIR=/usr/local/etc/sshvpn/keys

old=$(sha256 -q "${DROPIN}" 2>/dev/null)

/usr/local/sbin/configctl -q template reload OPNsense/Sshvpn

# StrictModes: keys file and its directories must not be group/world writable
chmod 0755 /usr/local/etc/sshvpn "${KEYDIR}" 2>/dev/null
chmod 0644 "${KEYDIR}/root" 2>/dev/null

/usr/local/opnsense/scripts/sshvpn/tunconf.py setup

new=$(sha256 -q "${DROPIN}" 2>/dev/null)

if [ "${old}" != "${new}" ]; then
    if /usr/local/sbin/sshd -t -f /usr/local/etc/ssh/sshd_config; then
        /usr/local/etc/rc.sshd
    else
        echo "sshvpn: sshd configuration test failed, not restarting sshd" >&2
        exit 1
    fi
fi

exit 0
