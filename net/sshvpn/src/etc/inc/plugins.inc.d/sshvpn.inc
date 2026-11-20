<?php

/*
 * Copyright (c) 2026 Bram Bardoul
 * SPDX-License-Identifier: BSD-2-Clause
 */

/*
 * SSH VPN plugin hooks (NetworkManager-ssh compatible server).
 *
 * There is no daemon of our own: tunnels run over the core OpenSSH service,
 * which picks up /usr/local/etc/ssh/sshd_config.d/50-sshvpn.conf.
 */

function sshvpn_enabled()
{
    $mdl = new \OPNsense\Sshvpn\Sshvpn();
    return (string)$mdl->general->enabled == '1';
}

function sshvpn_configure()
{
    return [
        'early' => ['sshvpn_configure_do'],
    ];
}

/**
 * At boot, before interfaces are configured: create the tun/tap devices so
 * assigned SSH VPN interfaces exist. The sshd drop-in is a persistent file.
 */
function sshvpn_configure_do($verbose = false)
{
    if (!sshvpn_enabled()) {
        return;
    }

    service_log('Creating SSH VPN interfaces...', $verbose);
    (new \OPNsense\Core\Backend())->configdRun('sshvpn setup');
    service_log("done.\n", $verbose);
}

/**
 * Interface group "sshvpn" so firewall rules can cover all tunnels
 * without assigning each tun/tap interface.
 */
function sshvpn_interfaces()
{
    $interfaces = [];

    if (!sshvpn_enabled()) {
        return $interfaces;
    }

    $interfaces['sshvpn'] = [
        'descr' => gettext('SSH VPN (Group)'),
        'if' => 'sshvpn',
        'virtual' => true,
        'enable' => true,
        'type' => 'group',
        'networks' => [],
    ];

    return $interfaces;
}

/**
 * Make the plugin's tun/tap devices available under Interfaces: Assignments.
 * Units are limited to 100-255 so the pattern does not overlap core tap0NN devices.
 */
function sshvpn_devices()
{
    $names = [];

    $mdl = new \OPNsense\Sshvpn\Sshvpn();
    if ((string)$mdl->general->enabled == '1') {
        foreach ($mdl->clients->client->iterateItems() as $client) {
            if ((string)$client->enabled != '1') {
                continue;
            }
            $ifname = (string)$client->mode . (string)$client->unit;
            $names[$ifname] = [
                'descr' => sprintf('%s (SSH VPN - %s)', $ifname, (string)$client->description),
                'ifdescr' => (string)$client->description,
                'name' => $ifname,
            ];
        }
    }

    return [[
        'function' => 'sshvpn_prepare',
        'typedescr' => gettext('SSH VPN'),
        'configurable' => false,
        'type' => 'sshvpn',
        'pattern' => '^(tun|tap)(1[0-9][0-9]|2[0-4][0-9]|25[0-5])$',
        'names' => $names,
    ]];
}

/**
 * Outbound NAT for clients with "Outbound NAT" enabled. Registered at the same
 * priority as the automatic outbound rules (200), so manual rules (50/100) win.
 * Without a target, pf translates to the interface address "(if:0)".
 */
function sshvpn_firewall($fw)
{
    global $config;

    if (!sshvpn_enabled()) {
        return;
    }

    $mdl = new \OPNsense\Sshvpn\Sshvpn();
    foreach ($mdl->clients->client->iterateItems() as $client) {
        if ((string)$client->enabled != '1' || (string)$client->nat != '1') {
            continue;
        }
        $fw->registerSourceNatRule(200, [
            'descr' => sprintf('SSH VPN NAT: %s', (string)$client->description),
            'interface' => (string)$client->nat_interface,
            'ipprotocol' => 'inet',
            'source' => ['network' => (string)$client->client_ip . '/32'],
            'destination' => ['any' => true],
            'log' => !empty($config['syslog']['logoutboundnat']),
        ]);
    }
}

function sshvpn_prepare($device)
{
    (new \OPNsense\Core\Backend())->configdpRun('sshvpn tunup', [$device]);
}
