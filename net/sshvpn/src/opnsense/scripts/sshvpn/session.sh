#!/bin/sh
# Copyright (c) 2026 Bram Bardoul
# SPDX-License-Identifier: BSD-2-Clause
#
# Forced command for SSH VPN client keys (see authorized_keys).
#
# NetworkManager-ssh sends Linux iproute2 commands such as
#   /sbin/ip addr add 10.0.0.1/255.255.255.252 peer 10.0.0.2/255.255.255.252 dev tun100; \
#   /sbin/ip link set mtu 1500 dev tun100 up
# which do not exist on FreeBSD. They arrive in $SSH_ORIGINAL_COMMAND and are
# deliberately ignored: the server side of the tunnel is configured from the
# OPNsense configuration for the interface pinned to this key.
#
# Output on stdout/stderr would be relayed to the client, so stay quiet.
# Once this exits the session channel closes, while the tun/tap channel stays
# open - exactly like the original Linux behaviour.
#

case "$1" in
tun[0-9]*|tap[0-9]*)
    /usr/local/opnsense/scripts/sshvpn/tunconf.py up "$1" >/dev/null 2>&1
    ;;
esac

logger -t sshvpn "session for $1 from ${SSH_CLIENT%% *}" 2>/dev/null
exit 0
