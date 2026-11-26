import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:shept_openapi_client_dart/api.dart';

import '../utils/singleton.dart';
import '../utils/utils.dart';

/// Devices signed into the account, with revoke and unrevoke.
///
/// Revoking is the hard lockout: the device loses its socket, its refresh
/// sessions and every request it makes from then on, even though it still holds
/// the account key.
class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key});

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  List<ModelsDevice> _devices = [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final response =
        await Utils.callApi(() => Singleton().userApi.getDevices());
    if (!mounted) {
      return;
    }
    setState(() {
      _devices = response?.devices ?? [];
      _loading = false;
    });
  }

  /// Revokes or unrevokes one device and refreshes the list.
  Future<void> _setRevoked(ModelsDevice device, bool revoke) async {
    if (_busy) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(revoke ? 'revokeDevice'.tr() : 'unrevokeDevice'.tr()),
        content: Text(revoke
            ? 'revokeDeviceConfirm'.tr(args: [device.label])
            : 'unrevokeDeviceConfirm'.tr(args: [device.label])),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('confirm'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() {
      _busy = true;
    });
    await Utils.callApi(() => revoke
        ? Singleton().userApi.revokeDevice(device.id)
        : Singleton().userApi.unrevokeDevice(device.id));
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
    });
    await Fluttertoast.showToast(
        msg: revoke ? 'deviceRevokedToast'.tr() : 'deviceUnrevokedToast'.tr(),
        backgroundColor: Colors.grey);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('devicesPage'.tr())),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView.builder(
                  itemCount: _devices.length,
                  itemBuilder: (context, index) {
                    final device = _devices[index];
                    final revoked = device.revokedAt != null;
                    return ListTile(
                      leading: Icon(
                        device.platform == 'android' || device.platform == 'ios'
                            ? Icons.smartphone
                            : Icons.computer,
                        color: revoked
                            ? Theme.of(context).disabledColor
                            : Theme.of(context).colorScheme.secondary,
                      ),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(
                              device.label,
                              overflow: TextOverflow.ellipsis,
                              style: revoked
                                  ? TextStyle(
                                      decoration: TextDecoration.lineThrough,
                                      color: Theme.of(context).disabledColor)
                                  : null,
                            ),
                          ),
                          if (device.current == true)
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: Text(
                                'thisDevice'.tr(),
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .secondary),
                              ),
                            ),
                        ],
                      ),
                      subtitle: Text(
                        revoked
                            ? 'deviceRevokedAt'.tr(args: [
                                DateFormat.yMd(context.locale.toString())
                                    .add_Hm()
                                    .format(device.revokedAt!.toLocal())
                              ])
                            : 'deviceLastSeen'.tr(args: [
                                DateFormat.yMd(context.locale.toString())
                                    .add_Hm()
                                    .format(device.lastSeenAt.toLocal())
                              ]),
                      ),
                      trailing: device.current == true
                          ? null
                          : TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _setRevoked(device, !revoked),
                              child: Text(
                                revoked ? 'unrevoke'.tr() : 'revoke'.tr(),
                                style: TextStyle(
                                    color: revoked
                                        ? Theme.of(context)
                                            .colorScheme
                                            .secondary
                                        : Colors.red),
                              ),
                            ),
                    );
                  },
                ),
              ),
      ),
    );
  }
}
