# os-sshvpn — SSH VPN for OPNsense (NetworkManager-ssh compatible)

An OPNsense plugin that turns the **built-in OPNsense SSH service** into a VPN endpoint for
Linux clients using [NetworkManager-ssh](https://github.com/danfruehauf/NetworkManager-ssh).
It adds **VPN → SSH VPN** to the web GUI.

SSH VPN tunnels IP traffic through a normal SSH connection (OpenSSH `-w` / `Tunnel`). That's
useful where only SSH gets through, or when you want a quick VPN without certificates.

> Unofficial community plugin, not affiliated with or supported by the OPNsense project.
> It changes how root can log in over SSH, so read [Security](#security) before using it.

## Features

- Uses the system SSH service. No second sshd, no extra port.
- Each client has its own public key, **pinned to its own tun/tap device**, with a forced
  command and no shell, pty, port or agent forwarding.
- NetworkManager-ssh's Linux `ip` commands are ignored. The firewall configures its own end of
  the tunnel with FreeBSD `ifconfig`.
- `SSH VPN` interface group for firewall rules; the tun/tap devices can also be assigned as
  interfaces.
- Optional **outbound NAT** per client, for internet access through the tunnel.
- Status tab: connected clients, traffic counters, host key fingerprints.
- Warns when a client key is also one of root's own login keys.

## Requirements

- OPNsense **26.x**. Tested on 26.7.9 (amd64) with OpenSSH 10.6p2.
- System SSH enabled (**System → Settings → Administration → Secure Shell**), reachable from
  where clients connect.
- Linux client with NetworkManager-ssh, using key authentication.

## Installation

The plugin isn't in the official OPNsense plugin repository, so you install it by copying the
files to the firewall. Root's login shell on OPNsense is csh, which is why the commands are
wrapped in `sh -c`.

```sh
git clone https://github.com/<you>/opnsense-sshvpn.git
cd opnsense-sshvpn/net/sshvpn/src

tar -cf - --exclude=__pycache__ . | ssh root@<firewall> "sh -c 'tar -xf - -C /usr/local --no-same-owner'"
ssh root@<firewall> "sh -c 'chmod +x /usr/local/opnsense/scripts/sshvpn/*; \
  service configd restart; service devd restart; \
  rm -f /var/lib/php/tmp/opnsense_menu_cache.xml /var/lib/php/tmp/opnsense_acl_cache.json; \
  configctl template reload OPNsense/Sshvpn'"
```

Reload the web GUI (Ctrl+F5); **VPN → SSH VPN** now appears.

Updates use the same commands. To uninstall, disable the plugin and click Apply first, then
remove the files under `/usr/local` that are listed in `net/sshvpn/src`.

To build a proper package instead, copy `net/sshvpn` into an
[opnsense/plugins](https://github.com/opnsense/plugins) checkout on a FreeBSD/OPNsense build
host and run `make package`.

## Configuration

### Firewall

1. **VPN → SSH VPN → General**: enable, then **Apply**.
2. **Clients → +**, one entry per client:
   - **Public key**: a key used only for this VPN (see [Security](#security))
   - **Device type**: tun (default) or tap. Must match the client.
   - **Device number**: 100–255, unique per client
   - **Server / Client tunnel IP** and **Netmask**, e.g. `10.99.0.1` / `10.99.0.2`, `/30`
   - optional IPv6 addresses, MTU, **Outbound NAT**

   Then click **Apply**.
3. **Firewall → Rules → WAN**: allow TCP to the SSH port, if clients come from the internet.
4. **Firewall → Rules → SSH VPN**: allow what the clients may reach.

### Client (NetworkManager-ssh)

| OPNsense                    | NetworkManager-ssh GUI             | keyfile (`[vpn]`) |
|-----------------------------|------------------------------------|-------------------|
| System SSH port             | Port                               | `port`            |
| —                           | Remote username: **root**          | `remote-username` |
| Public key                  | Auth type "SSH key" + key file     | `auth-type=key`, `key-file` |
| Device type                 | Use a TAP device                   | `tap-dev`         |
| Device number               | Remote device number (default 100) | `remote-dev`      |
| Server tunnel IP            | Remote IP Address                  | `remote-ip`       |
| Client tunnel IP            | Local IP Address                   | `local-ip`        |
| Netmask                     | Netmask                            | `netmask`         |
| Server / Client IPv6        | Remote / Local IPv6 Address        | `remote-ip-6`, `local-ip-6` |
| IPv6 prefix length          | IPv6 Netmask                       | `netmask-6`       |
| MTU                         | Tunnel MTU                         | `tunnel-mtu`      |

Example `/etc/NetworkManager/system-connections/fw.nmconnection`:

```ini
[connection]
id=fw-ssh
type=vpn

[vpn]
service-type=org.freedesktop.NetworkManager.ssh
remote=fw.example.org
port=22
remote-username=root
auth-type=key
key-file=/home/me/.ssh/id_sshvpn
remote-dev=100
remote-ip=10.99.0.1
local-ip=10.99.0.2
netmask=255.255.255.252
tunnel-mtu=1500

[ipv4]
method=auto
# split tunnel: only these networks go through the VPN
never-default=true
route1=192.168.1.0/24,10.99.0.1
# full tunnel instead: never-default=false and enable Outbound NAT on the firewall
```

Accept the firewall's host key once before the first connection, because NetworkManager-ssh
won't prompt for it: `ssh -i ~/.ssh/id_sshvpn root@fw.example.org` (it exits right away;
that's fine). Compare the key with the fingerprints on the **Status** tab.

Not supported: password authentication (sshpass), "Use sudo" (ignored, not needed), SOCKS
mode and `-L`/`-R` forwards.

## Security

- **Use a dedicated key per VPN client.** sshd checks root's own `~/.ssh/authorized_keys`
  before the plugin's keys file. If a client key is also one of root's admin keys, that entry
  matches first and the client gets an **unrestricted root login**: no forced command, no
  pinned device, forwarding allowed. The tunnel may still work, which hides the problem. The
  Clients tab shows a yellow warning in that case.
- VPN keys can't get a shell, a pty, or port/agent/X11 forwarding, and are pinned to their
  tun/tap unit.
- NetworkManager-ssh always logs in as **root**. If root login is disabled system-wide, the
  option **Permit root VPN logins** (default on) sets `PermitRootLogin forced-commands-only`
  for root. Root can then log in only with keys that carry a forced command, i.e. the VPN keys.
  With the option off, VPN logins fail while root login is disabled.
- Opening the SSH port on WAN exposes the administrative SSH service too. Keep password
  authentication off.

## How it works

NetworkManager-ssh runs roughly:

```
ssh -o Tunnel=point-to-point -o TunnelDevice=<local>:100 -o User=root <host> \
  "/sbin/ip addr add R/M peer L/M dev tun100; /sbin/ip link set mtu 1500 dev tun100 up"
```

The core OPNsense `sshd_config` starts with `Include /usr/local/etc/ssh/sshd_config.d/*.conf`.
The plugin adds `50-sshvpn.conf`:

```
Match User root
	PermitTunnel yes
	AuthorizedKeysFile .ssh/authorized_keys .ssh/authorized_keys2 /usr/local/etc/sshvpn/keys/%u
	PermitRootLogin forced-commands-only     # only if root login is disabled system-wide
```

The `Match` block applies only to root and ends with the included file. Port, listen
interfaces, host keys, ciphers and the password policy all stay as configured in the GUI.

Each client key in `/usr/local/etc/sshvpn/keys/root` is written as:

```
no-port-forwarding,no-agent-forwarding,no-X11-forwarding,no-pty,no-user-rc,tunnel="N",command=".../session.sh tunN" <key>
```

`restrict` is **not** used on purpose. OpenSSH refuses tun forwarding for keys with `restrict`
("Server has rejected tunnel device forwarding"; `auth_opts->restricted` in `serverloop.c`).
The explicit list applies the same five restrictions without that flag.

- `tunnel="N"` forces the server-side unit, whatever the client asks for.
- The forced command, `session.sh`, ignores the Linux command and runs `tunconf.py up tunN`,
  which sets the addresses with `ifconfig`. A devd hook does the same on link-up, for clients
  using "No remote command" (`-N`).

**Apply** (`configctl sshvpn reconfigure`) does the following:
1. renders the templates
2. creates, configures or removes the tun/tap interfaces
3. restarts sshd (`rc.sshd`) only if the drop-in changed. Client changes need no restart,
   because sshd reads the keys file at every login. Established SSH sessions survive a restart.
4. re-registers interfaces and reloads the firewall filter, including the NAT rules from
   `sshvpn_firewall()`: `nat on <if> inet from <client-ip>/32 to any -> (<if>:0)`, at the
   priority of the automatic rules, so manual NAT rules still win

Tunnel interfaces are created at boot (`early` hook).

## Troubleshooting

| Symptom | Where to look |
|---|---|
| GUI: "Error reconfiguring SSH VPN" / "Unexpected error" | `/var/lib/php/tmp/PHP_errors.log` |
| `configctl template reload OPNsense/Sshvpn` prints `ERR` | `/var/log/configd/latest.log` |
| Client can't log in | auth log (`sshd`). Effective config: `sshd -T -C user=root,host=x,addr=1.2.3.4 \| grep -iE 'permittunnel\|authorizedkeysfile\|permitrootlogin'` |
| Client: "Server has rejected tunnel device forwarding" | plugin disabled / not applied, or a key line containing `restrict` |
| Client: "Tunnel device open failed on remote server" | device already in use (one session per key), or tun/tap mismatch |
| Connected, but no `sshvpn: session for tunN` line in the system log | the client authenticated with one of root's own keys (see [Security](#security)) |
| Tunnel up, no internet | Outbound NAT off for the client, missing pass rule on the SSH VPN group, or client routes |
| New menu entry or icon not showing | delete `/var/lib/php/tmp/opnsense_menu_cache.xml`, then Ctrl+F5 |

Useful commands on the firewall (wrap in `sh -c '…'` when run via ssh):
`configctl sshvpn sessions`, `ifconfig -g sshvpn`, `pfctl -s nat | grep <client-ip>`.

Careful: `rc.sshd` stops sshd with `pkill -af /usr/local/sbin/sshd`, which kills any process
whose command line contains that path. Don't put that path in the same remote command as
`configctl sshvpn reconfigure`, or your SSH session will be killed.

## Limitations

- One active session per client, because the tun/tap unit is exclusive.
- Outbound NAT is IPv4 only.
- Clients don't receive routes or DNS from the server. Configure them on the client.

## License

BSD 2-Clause, the same as OPNsense. See [LICENSE](LICENSE).
