#!/usr/local/bin/python3
# Copyright (c) 2026 Bram Bardoul
# SPDX-License-Identifier: BSD-2-Clause

"""
Print the public keys root accepts outside the SSH VPN plugin, as JSON:
[{"type": "ssh-rsa", "blob": "AAAA...", "comment": "...", "file": "..."}]

Used by the GUI to warn when a VPN client key is also one of root's own keys.
sshd checks .ssh/authorized_keys before the plugin's keys file, so such a key
logs in without the forced command, tunnel pinning and forwarding restrictions.
"""

import json
import re

FILES = ['/root/.ssh/authorized_keys', '/root/.ssh/authorized_keys2']
KEY_RE = re.compile(
    r'(?:^|[\s,"])((?:ssh-ed25519|ssh-rsa|ssh-dss|ecdsa-sha2-nistp(?:256|384|521)|'
    r'sk-ssh-ed25519@openssh\.com|sk-ecdsa-sha2-nistp256@openssh\.com))\s+([A-Za-z0-9+/]+={0,3})(?:\s+(.*))?$'
)

result = []
for path in FILES:
    try:
        with open(path) as fh:
            for line in fh:
                line = line.strip()
                if not line or line.startswith('#'):
                    continue
                m = KEY_RE.search(line)
                if m:
                    result.append({'type': m.group(1), 'blob': m.group(2), 'comment': (m.group(3) or '').strip(), 'file': path})
    except OSError:
        pass

print(json.dumps(result))
