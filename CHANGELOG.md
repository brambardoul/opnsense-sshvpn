# Changelog

## 0.1 — 2026-11-20

First public release.

- Uses the built-in OPNsense SSH service (sshd drop-in in `sshd_config.d`, `Match User root`).
  No second sshd instance.
- Per-client public key pinned to its own tun/tap unit (100–255), forced command, no shell,
  pty, port forwarding or agent forwarding.
- Linux `ip` commands from NetworkManager-ssh are ignored; the firewall side is configured
  with FreeBSD `ifconfig`, plus a devd hook for clients using "No remote command".
- Optional "Permit root VPN logins" (`PermitRootLogin forced-commands-only` for root) when root
  login is disabled system-wide.
- `sshvpn` interface group for firewall rules; devices can be assigned as interfaces.
- Optional per-client outbound NAT (IPv4) to a chosen interface.
- Status tab: connected clients, byte counters, host key fingerprints.
- Warning (doesn't block saving) when a client key is also one of root's own authorized keys.
- Tested on OPNsense 26.7.9 (amd64) / OpenSSH 10.6p2 with NetworkManager-ssh on Linux.
