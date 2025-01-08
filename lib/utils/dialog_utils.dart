import 'package:easy_localization/easy_localization.dart';
import 'package:email_validator/email_validator.dart';
import 'package:flutter/material.dart';
import 'package:whisper_openapi_client/api.dart';

import 'singleton.dart';
import 'utils.dart';

class DialogUtils {

  /// Returns new invite dialog
  static Widget newInviteDialog(BuildContext context) {
    final TextEditingController controllerMail = TextEditingController();
    bool mailOk = false;
    bool mailEditing = false;

    String? errorMail() {
      if (!EmailValidator.validate(controllerMail.text) && mailEditing) {
        return 'invalidMail'.tr();
      }
      if (EmailValidator.validate(controllerMail.text)) {
        mailOk = true;
      }
      return null;
    }

    /// Creates invite
    Future<void> createInvite() async {
      if (mailOk) {
        await Utils.callApi(
            () => Singleton().inviteApi.createInvite(
                createInviteInput:
                    CreateInviteInput(mail: controllerMail.text)),
            true);
        if (context.mounted) {
          Navigator.pop(context);
        }
      }
    }

    return StatefulBuilder(builder: (context, setState) {
      return AlertDialog(
        title: Text('newInvite'.tr()),
        content: SizedBox(
          width: MediaQuery.of(context).size.width / 4,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controllerMail,
                onChanged: (_) => setState(() {
                  mailEditing = true;
                }),
                decoration: InputDecoration(
                    errorText: errorMail(), hintText: 'userMail'.tr()),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: TextButton(
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.all(
                        Theme.of(context).colorScheme.primary),
                    shape: WidgetStateProperty.all<RoundedRectangleBorder>(
                      RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(35)),
                    ),
                  ),
                  onPressed: createInvite,
                  child: Padding(
                    padding: EdgeInsets.all(7),
                    child: Text(
                      'newInvite'.tr(),
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.surface,
                          fontSize: 16),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}
