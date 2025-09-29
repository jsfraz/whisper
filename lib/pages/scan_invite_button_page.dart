import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'scan_invite_page.dart';

class ScanInviteButtonPage extends StatefulWidget {
  const ScanInviteButtonPage({super.key});

  @override
  State<ScanInviteButtonPage> createState() => _ScanInviteButtonPageState();
}

class _ScanInviteButtonPageState extends State<ScanInviteButtonPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.all(
                      Theme.of(context).colorScheme.primary),
                  shape: WidgetStateProperty.all<RoundedRectangleBorder>(
                    RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(35)),
                  ),
                ),
                onPressed: () {
                  // Navigate to scanning invite
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const ScanInvitePage()));
                },
                child: Padding(
                  padding: const EdgeInsets.all(7),
                  child: Text(
                    'scanQrButton'.tr(),
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.surface,
                        fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
