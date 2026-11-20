<?php

/*
 * Copyright (c) 2026 Bram Bardoul
 * SPDX-License-Identifier: BSD-2-Clause
 */

namespace OPNsense\Sshvpn\Api;

use OPNsense\Base\ApiMutableModelControllerBase;
use OPNsense\Core\Backend;

class ClientsController extends ApiMutableModelControllerBase
{
    protected static $internalModelName = 'client';
    protected static $internalModelClass = '\OPNsense\Sshvpn\Sshvpn';

    public function searchClientAction()
    {
        return $this->searchBase(
            'clients.client',
            ['enabled', 'description', 'mode', 'unit', 'server_ip', 'client_ip', 'netmask', 'server_ip6', 'client_ip6', 'nat']
        );
    }

    public function getClientAction($uuid = null)
    {
        return $this->getBase('client', 'clients.client', $uuid);
    }

    public function addClientAction()
    {
        return $this->addBase('client', 'clients.client');
    }

    public function setClientAction($uuid)
    {
        return $this->setBase('client', 'clients.client', $uuid);
    }

    public function delClientAction($uuid)
    {
        return $this->delBase('clients.client', $uuid);
    }

    public function toggleClientAction($uuid, $enabled = null)
    {
        return $this->toggleBase('clients.client', $uuid, $enabled);
    }

    /**
     * Warning only (never blocks saving): clients whose key is also in root's own
     * authorized_keys. sshd matches that entry first, so the VPN restrictions
     * (forced command, pinned tun unit, no forwarding) do not apply.
     */
    public function keyConflictsAction()
    {
        $rootkeys = json_decode((new Backend())->configdRun('sshvpn rootkeys'), true);
        $byblob = [];
        foreach (is_array($rootkeys) ? $rootkeys : [] as $key) {
            if (!empty($key['blob'])) {
                $byblob[$key['blob']] = $key;
            }
        }

        $conflicts = [];
        foreach ($this->getModel()->clients->client->iterateItems() as $uuid => $client) {
            $parts = preg_split('/\s+/', trim((string)$client->pubkey));
            if (count($parts) >= 2 && isset($byblob[$parts[1]])) {
                $conflicts[] = [
                    'uuid' => $uuid,
                    'description' => (string)$client->description,
                    'enabled' => (string)$client->enabled == '1',
                    'rootkey_comment' => $byblob[$parts[1]]['comment'],
                    'file' => $byblob[$parts[1]]['file'],
                ];
            }
        }
        return ['conflicts' => $conflicts];
    }
}
