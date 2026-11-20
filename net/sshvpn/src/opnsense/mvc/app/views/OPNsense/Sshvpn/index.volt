{# Copyright (c) 2026 Bram Bardoul #}
{# SPDX-License-Identifier: BSD-2-Clause #}
{#
 # SSH VPN (NetworkManager-ssh compatible) settings page
 #}

<script>
    $(document).ready(function () {
        mapDataToFormUI({'frm_general': "/api/sshvpn/general/get"}).done(function () {
            $('.selectpicker').selectpicker('refresh');
        });

        function loadInfo() {
            ajaxGet('/api/sshvpn/service/info', {}, function (data) {
                const $box = $("#sshinfo").empty().removeClass('alert-info alert-warning');
                if (!data.ssh_enabled) {
                    $box.addClass('alert-warning').text("{{ lang._('The system SSH service is disabled. Enable it under System: Settings: Administration, otherwise clients cannot connect.') }}");
                } else {
                    let msg = "{{ lang._('Clients connect to the system SSH service on port') }} " + data.ssh_port;
                    msg += data.ssh_interfaces ? " ({{ lang._('listening on') }}: " + data.ssh_interfaces + ")" : " ({{ lang._('all interfaces') }})";
                    msg += ". {{ lang._('Allow this port in the firewall rules of the interface clients arrive on.') }}";
                    if (!data.ssh_rootlogin) {
                        msg += " {{ lang._('Root login is disabled system-wide; VPN keys depend on \"Permit root VPN logins\".') }}";
                    }
                    $box.addClass('alert-info').text(msg);
                }
                $box.show();
            });
        }
        loadInfo();

        $("#grid-clients").UIBootgrid({
            search: '/api/sshvpn/clients/searchClient',
            get: '/api/sshvpn/clients/getClient/',
            set: '/api/sshvpn/clients/setClient/',
            add: '/api/sshvpn/clients/addClient/',
            del: '/api/sshvpn/clients/delClient/',
            toggle: '/api/sshvpn/clients/toggleClient/'
        }).on("loaded.rs.jquery.bootgrid", loadKeyConflicts);

        // Non-blocking warning: VPN key that is also one of root's own authorized keys
        function loadKeyConflicts() {
            ajaxGet('/api/sshvpn/clients/keyConflicts', {}, function (data) {
                const $box = $("#keyconflicts");
                const conflicts = (data && Array.isArray(data.conflicts)) ? data.conflicts : [];
                if (conflicts.length === 0) {
                    $box.hide();
                    return;
                }
                const $list = $('<ul>');
                conflicts.forEach(function (c) {
                    let txt = c.description + " — {{ lang._('same key as') }} \"" + (c.rootkey_comment || '?') + "\" (" + c.file + ")";
                    if (!c.enabled) {
                        txt += " [{{ lang._('client disabled') }}]";
                    }
                    $list.append($('<li>').text(txt));
                });
                $box.empty()
                    .append($('<strong>').text("{{ lang._('Warning: VPN key is also an administrative root key.') }}"))
                    .append($('<p>').text("{{ lang._('sshd checks the authorized_keys of root first, so these clients log in as an unrestricted root user: the forced command, the pinned tun/tap unit and the forwarding restrictions do not apply. The tunnel may still work. Use a dedicated key per VPN client, or remove the key from System: Access: Users.') }}"))
                    .append($list)
                    .show();
            });
        }

        function loadStatus() {
            ajaxGet('/api/sshvpn/service/sessions', {}, function (data) {
                const $tbody = $("#sessions tbody").empty();
                if (!Array.isArray(data) || data.length === 0) {
                    $tbody.append($('<tr>').append($('<td colspan="7">').text("{{ lang._('No clients configured.') }}")));
                    return;
                }
                data.forEach(function (row) {
                    const state = row.connected ? "{{ lang._('connected') }}" : (row.exists ? "{{ lang._('idle') }}" : "{{ lang._('missing') }}");
                    $tbody.append($('<tr>')
                        .append($('<td>').text(row.description || ''))
                        .append($('<td>').text(row.interface || ''))
                        .append($('<td>').text(state))
                        .append($('<td>').text(row.pid || ''))
                        .append($('<td>').text((row.server_ip || '') + ' ↔ ' + (row.client_ip || '')))
                        .append($('<td>').text(row.ibytes !== undefined ? row.ibytes : ''))
                        .append($('<td>').text(row.obytes !== undefined ? row.obytes : '')));
                });
            });
            ajaxGet('/api/sshvpn/service/fingerprints', {}, function (data) {
                const $pre = $("#fingerprints").empty();
                $pre.text((data.fingerprints || []).join("\n"));
            });
        }

        $('a[href="#status"]').on('shown.bs.tab', loadStatus);
        $("#refreshStatus").click(loadStatus);

        $("#reconfigureAct").SimpleActionButton({
            onPreAction: function () {
                const dfObj = $.Deferred();
                saveFormToEndpoint("/api/sshvpn/general/set", 'frm_general', function () {
                    dfObj.resolve();
                }, true, function () {
                    dfObj.reject();
                });
                return dfObj;
            },
            onAction: function () {
                loadInfo();
            }
        });
    });
</script>

<div id="sshinfo" class="alert" role="alert" style="display: none"></div>

<ul class="nav nav-tabs" data-tabs="tabs" id="maintabs">
    <li class="active"><a data-toggle="tab" href="#general">{{ lang._('General') }}</a></li>
    <li><a data-toggle="tab" href="#clients">{{ lang._('Clients') }}</a></li>
    <li><a data-toggle="tab" href="#status">{{ lang._('Status') }}</a></li>
</ul>

<div class="tab-content content-box">
    <div id="general" class="tab-pane fade in active">
        {{ partial("layout_partials/base_form", ['fields': generalForm, 'id': 'frm_general']) }}
    </div>

    <div id="clients" class="tab-pane fade in">
        <div id="keyconflicts" class="alert alert-warning" role="alert" style="display: none; margin: 10px;"></div>
        <table id="grid-clients" class="table table-condensed table-hover table-striped" data-editDialog="DialogClient" data-editAlert="ChangeMessageChangeMessage">
            <thead>
                <tr>
                    <th data-column-id="uuid" data-type="string" data-identifier="true" data-visible="false">{{ lang._('ID') }}</th>
                    <th data-column-id="enabled" data-width="6em" data-type="string" data-formatter="rowtoggle">{{ lang._('Enabled') }}</th>
                    <th data-column-id="description" data-type="string">{{ lang._('Description') }}</th>
                    <th data-column-id="mode" data-type="string">{{ lang._('Type') }}</th>
                    <th data-column-id="unit" data-type="string">{{ lang._('Unit') }}</th>
                    <th data-column-id="server_ip" data-type="string">{{ lang._('Server IP') }}</th>
                    <th data-column-id="client_ip" data-type="string">{{ lang._('Client IP') }}</th>
                    <th data-column-id="netmask" data-type="string">{{ lang._('Netmask') }}</th>
                    <th data-column-id="nat" data-width="6em" data-type="string" data-formatter="boolean">{{ lang._('NAT') }}</th>
                    <th data-column-id="commands" data-width="7em" data-formatter="commands" data-sortable="false">{{ lang._('Commands') }}</th>
                </tr>
            </thead>
            <tbody></tbody>
            <tfoot>
                <tr>
                    <td></td>
                    <td>
                        <button data-action="add" type="button" class="btn btn-xs btn-primary"><span class="fa fa-fw fa-plus"></span></button>
                        <button data-action="deleteSelected" type="button" class="btn btn-xs btn-default"><span class="fa fa-fw fa-trash-o"></span></button>
                    </td>
                </tr>
            </tfoot>
        </table>
        <div class="col-md-12">
            <div id="ChangeMessageChangeMessage" class="alert alert-info" style="display: none" role="alert">
                {{ lang._('After changing settings, please remember to apply them with the button below.') }}
            </div>
        </div>
    </div>

    <div id="status" class="tab-pane fade in">
        <table id="sessions" class="table table-condensed table-striped">
            <thead>
                <tr>
                    <th>{{ lang._('Client') }}</th>
                    <th>{{ lang._('Interface') }}</th>
                    <th>{{ lang._('State') }}</th>
                    <th>{{ lang._('sshd PID') }}</th>
                    <th>{{ lang._('Tunnel') }}</th>
                    <th>{{ lang._('Bytes in') }}</th>
                    <th>{{ lang._('Bytes out') }}</th>
                </tr>
            </thead>
            <tbody></tbody>
        </table>
        <div class="col-md-12">
            <h4>{{ lang._('Host key fingerprints') }}</h4>
            <pre id="fingerprints"></pre>
            <button class="btn btn-default" id="refreshStatus" type="button">{{ lang._('Refresh') }}</button>
            <br/><br/>
        </div>
    </div>
</div>

<section class="page-content-main">
    <div class="content-box">
        <div class="col-md-12">
            <br/>
            <button class="btn btn-primary" id="reconfigureAct"
                    data-endpoint="/api/sshvpn/service/reconfigure"
                    data-label="{{ lang._('Apply') }}"
                    data-error-title="{{ lang._('Error reconfiguring SSH VPN') }}"
                    type="button"></button>
            <br/><br/>
        </div>
    </div>
</section>

{{ partial("layout_partials/base_dialog", ['fields': formDialogClient, 'id': 'DialogClient', 'label': lang._('Edit client')]) }}
