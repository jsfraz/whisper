import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

import '../utils/biometric_auth.dart';
import '../utils/cache_utils.dart';
import '../utils/singleton.dart';

/// Changes the local password: verifies the current one, re-encrypts the
/// profile and media under the key derived from the new one, and keeps
/// biometric unlock in sync.
class ChangePasswordDialog extends StatefulWidget {
  const ChangePasswordDialog({super.key});

  @override
  State<ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<ChangePasswordDialog> {
  final TextEditingController _current = TextEditingController();
  final TextEditingController _next = TextEditingController();
  final TextEditingController _confirmation = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final next = _next.text;
    if (next.length < 8 || next.length > 64) {
      setState(() {
        _error = 'invalidPassword'.tr();
      });
      return;
    }
    if (next != _confirmation.text) {
      setState(() {
        _error = 'passwordMismatch'.tr();
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final changed = await CacheUtils.changePassword(_current.text, next);
      if (!mounted) {
        return;
      }
      if (!changed) {
        setState(() {
          _busy = false;
          _error = 'wrongCurrentPassword'.tr();
        });
        return;
      }
      // Biometrics store a copy of the derived key; it must follow the change,
      // otherwise fingerprint unlock would open the boxes with a stale key.
      if (await CacheUtils.isBiometryEnabled()) {
        if (!mounted) {
          return;
        }
        final stored = await BiometricAuth.storeEncryptionKey(
            Singleton().boxCollectionKey, context);
        if (!stored) {
          await BiometricAuth.clearEncryptionKey();
          await CacheUtils.setBiometryEnabled(false);
        }
        if (!mounted) {
          return;
        }
      }
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint('change password failed: $e');
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
      });
      await Fluttertoast.showToast(
          msg: 'passwordChangeFailed'.tr(), backgroundColor: Colors.red);
    }
  }

  Widget _field(TextEditingController controller, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: controller,
        obscureText: true,
        enabled: !_busy,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('changePassword'.tr()),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _field(_current, 'currentPassword'.tr()),
            _field(_next, 'newPassword'.tr()),
            _field(_confirmation, 'confirmPassword'.tr()),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: Text('noText'.tr()),
        ),
        TextButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator())
              : Text('okText'.tr()),
        ),
      ],
    );
  }
}
