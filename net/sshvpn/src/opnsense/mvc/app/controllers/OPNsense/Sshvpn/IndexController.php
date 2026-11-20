<?php

/*
 * Copyright (c) 2026 Bram Bardoul
 * SPDX-License-Identifier: BSD-2-Clause
 */

namespace OPNsense\Sshvpn;

class IndexController extends \OPNsense\Base\IndexController
{
    public function indexAction()
    {
        $this->view->generalForm = $this->getForm('general');
        $this->view->formDialogClient = $this->getForm('dialogClient');
        $this->view->pick('OPNsense/Sshvpn/index');
    }
}
