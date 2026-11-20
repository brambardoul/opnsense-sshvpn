#!/usr/local/bin/python3
# Copyright (c) 2026 Bram Bardoul
# SPDX-License-Identifier: BSD-2-Clause

"""
Manage tun/tap interfaces of the SSH VPN plugin.

    tunconf.py setup         create + configure all configured interfaces, remove stale ones
    tunconf.py up <ifname>   (re)configure one interface (called from forced command / devd)
    tunconf.py teardown      destroy all plugin interfaces
    tunconf.py status        JSON status for the GUI
"""

import ipaddress
import json
import re
import subprocess
import sys
import time

CONF = '/usr/local/etc/sshvpn/tunnels.conf'
GROUP = 'sshvpn'
IFCONFIG = '/sbin/ifconfig'
NETSTAT = '/usr/bin/netstat'
IFNAME_RE = re.compile(r'^(tun|tap)([0-9]{1,3})$')


def run(*args, check=False):
    return subprocess.run(list(args), capture_output=True, text=True, check=check)


def load_tunnels():
    tunnels = {}
    try:
        with open(CONF) as fh:
            for line in fh:
                line = line.strip()
                if not line or line.startswith('#'):
                    continue
                parts = line.split('|', 9)
                if len(parts) != 10:
                    continue
                mode, unit, sip, cip, mask, mtu, sip6, cip6, pfx6, descr = parts
                if mode not in ('tun', 'tap') or not unit.isdigit():
                    continue
                try:
                    ipaddress.IPv4Address(sip)
                    ipaddress.IPv4Address(cip)
                    ipaddress.IPv4Network('0.0.0.0/%s' % mask)
                    if sip6 or cip6:
                        ipaddress.IPv6Address(sip6)
                        ipaddress.IPv6Address(cip6)
                except ValueError:
                    continue
                name = '%s%d' % (mode, int(unit))
                tunnels[name] = {
                    'interface': name,
                    'mode': mode,
                    'server_ip': sip,
                    'client_ip': cip,
                    'netmask': mask,
                    'mtu': int(mtu) if mtu.isdigit() else 1500,
                    'server_ip6': sip6,
                    'client_ip6': cip6,
                    'prefix6': int(pfx6) if pfx6.isdigit() else 128,
                    'description': descr,
                }
    except FileNotFoundError:
        pass
    return tunnels


def if_exists(name):
    return run(IFCONFIG, name).returncode == 0


def group_members():
    res = run(IFCONFIG, '-g', GROUP)
    if res.returncode != 0:
        return []
    return [x for x in res.stdout.split() if IFNAME_RE.match(x)]


def configure(t):
    name = t['interface']
    if not if_exists(name):
        run(IFCONFIG, name, 'create')
    run(IFCONFIG, name, 'group', GROUP)
    run(IFCONFIG, name, 'description', 'sshvpn: %s' % t['description'])
    run(IFCONFIG, name, 'mtu', str(t['mtu']))

    if t['mode'] == 'tun':
        # point-to-point, mirrors "ip addr add R/M peer L/M" on the Linux side
        run(IFCONFIG, name, 'inet', t['server_ip'], t['client_ip'], 'netmask', t['netmask'])
    else:
        run(IFCONFIG, name, 'inet', '%s/%s' % (t['server_ip'], t['netmask']))

    if t['server_ip6']:
        run(IFCONFIG, name, 'inet6', '-ifdisabled')
        if t['mode'] == 'tun' and t['prefix6'] == 128:
            run(IFCONFIG, name, 'inet6', t['server_ip6'], t['client_ip6'], 'prefixlen', '128')
        else:
            run(IFCONFIG, name, 'inet6', t['server_ip6'], 'prefixlen', str(t['prefix6']))

    run(IFCONFIG, name, 'up')


def cmd_setup():
    tunnels = load_tunnels()
    for t in tunnels.values():
        configure(t)
    for name in group_members():
        if name not in tunnels:
            run(IFCONFIG, name, 'destroy')


def cmd_up(name):
    m = IFNAME_RE.match(name or '')
    if not m:
        return 1
    tunnels = load_tunnels()
    if name not in tunnels:
        return 1
    # sshd opens the device right before running the forced command; give it a moment
    for _ in range(10):
        if if_exists(name):
            break
        time.sleep(0.2)
    configure(tunnels[name])
    return 0


def cmd_teardown():
    for name in group_members():
        run(IFCONFIG, name, 'destroy')


def iface_counters(name):
    res = run(NETSTAT, '-I', name, '-b', '-n', '--libxo', 'json')
    try:
        data = json.loads(res.stdout)
        for row in data.get('statistics', {}).get('interface', []):
            if row.get('name') == name and 'received-bytes' in row:
                return int(row.get('received-bytes', 0)), int(row.get('sent-bytes', 0))
    except (ValueError, TypeError, AttributeError):
        pass
    return None, None


def cmd_status():
    result = []
    for name, t in sorted(load_tunnels().items()):
        entry = {
            'interface': name,
            'description': t['description'],
            'server_ip': t['server_ip'],
            'client_ip': t['client_ip'],
            'exists': False,
            'connected': False,
            'pid': None,
        }
        res = run(IFCONFIG, name)
        if res.returncode == 0:
            entry['exists'] = True
            m = re.search(r'Opened by PID (\d+)', res.stdout)
            if m:
                entry['connected'] = True
                entry['pid'] = int(m.group(1))
            ibytes, obytes = iface_counters(name)
            if ibytes is not None:
                entry['ibytes'] = ibytes
                entry['obytes'] = obytes
        result.append(entry)
    print(json.dumps(result))


def main(argv):
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 1
    action = argv[1]
    if action == 'setup':
        cmd_setup()
    elif action == 'up':
        return cmd_up(argv[2] if len(argv) > 2 else '')
    elif action == 'teardown':
        cmd_teardown()
    elif action == 'status':
        cmd_status()
    else:
        print(__doc__, file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
