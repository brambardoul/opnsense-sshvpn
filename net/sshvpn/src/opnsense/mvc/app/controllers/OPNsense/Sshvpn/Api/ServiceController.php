<?php

/*
 * Copyright (c) 2026 Bram Bardoul
 * SPDX-License-Identifier: BSD-2-Clause
 */

namespace OPNsense\Sshvpn\Api;

use OPNsense\Base\ApiControllerBase;
use OPNsense\Core\Backend;
use OPNsense\Core\Config;

/**
 * No daemon of our own: the plugin piggybacks on the core OpenSSH service.
 */
class ServiceController extends ApiControllerBase
{
    public function reconfigureAction()
    {
        if (!$this->request->isPost()) {
            return ['status' => 'failed'];
        }
        $backend = new Backend();
        $result = trim($backend->configdRun('sshvpn reconfigure'));

        /* (de)register the "sshvpn" interface group and tun/tap devices, refresh rules */
        $this->runInterfaceRegistration();
        $backend->configdRun('filter reload skip_alias');

        return ['status' => $result === 'OK' ? 'ok' : 'failed', 'result' => $result];
    }

    /**
     * State of the core SSH service as far as it matters for the VPN.
     */
    public function infoAction()
    {
        $ssh = Config::getInstance()->object()->system->ssh ?? null;
        return [
            'ssh_enabled' => $ssh !== null && isset($ssh->enabled),
            'ssh_port' => ($ssh !== null && !empty((string)$ssh->port)) ? (string)$ssh->port : '22',
            'ssh_interfaces' => ($ssh !== null && !empty((string)$ssh->interfaces)) ? (string)$ssh->interfaces : '',
            'ssh_rootlogin' => $ssh !== null && isset($ssh->permitrootlogin),
        ];
    }

    public function sessionsAction()
    {
        $result = json_decode((new Backend())->configdRun('sshvpn sessions'), true);
        return is_array($result) ? $result : [];
    }

    public function fingerprintsAction()
    {
        $out = trim((new Backend())->configdRun('sshvpn fingerprints'));
        return ['fingerprints' => $out === '' ? [] : explode("\n", $out)];
    }
}
