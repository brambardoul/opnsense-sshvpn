<?php

/*
 * Copyright (c) 2026 Bram Bardoul
 * SPDX-License-Identifier: BSD-2-Clause
 */

/*
 * SSH VPN plugin model (NetworkManager-ssh compatible server side).
 */

namespace OPNsense\Sshvpn;

use OPNsense\Base\BaseModel;
use OPNsense\Base\Messages\Message;

class Sshvpn extends BaseModel
{
    public function performValidation($validateFullModel = false)
    {
        $messages = parent::performValidation($validateFullModel);

        foreach ($this->clients->client->iterateItems() as $client) {
            if (!$validateFullModel && !$client->isFieldChanged()) {
                continue;
            }
            $key = $client->__reference;

            if ((string)$client->server_ip !== '' && (string)$client->server_ip === (string)$client->client_ip) {
                $messages->appendMessage(new Message(
                    gettext('Server and client tunnel addresses must differ.'),
                    $key . '.client_ip'
                ));
            }

            $s6 = (string)$client->server_ip6;
            $c6 = (string)$client->client_ip6;
            if (($s6 === '') !== ($c6 === '')) {
                $messages->appendMessage(new Message(
                    gettext('Set both IPv6 addresses, or neither.'),
                    $key . ($s6 === '' ? '.server_ip6' : '.client_ip6')
                ));
            } elseif ($s6 !== '' && $s6 === $c6) {
                $messages->appendMessage(new Message(
                    gettext('Server and client IPv6 addresses must differ.'),
                    $key . '.client_ip6'
                ));
            }
        }

        return $messages;
    }
}
