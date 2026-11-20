<?php

/*
 * Copyright (c) 2026 Bram Bardoul
 * SPDX-License-Identifier: BSD-2-Clause
 */

namespace OPNsense\Sshvpn\Api;

use OPNsense\Base\ApiMutableModelControllerBase;

class GeneralController extends ApiMutableModelControllerBase
{
    protected static $internalModelName = 'sshvpn';
    protected static $internalModelClass = '\OPNsense\Sshvpn\Sshvpn';
}
