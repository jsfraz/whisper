import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';

import '../models/invite_data.dart';
import 'register_page.dart';

class ScanInvitePage extends StatefulWidget {
  const ScanInvitePage({super.key});

  @override
  State<ScanInvitePage> createState() => _ScanInvitePageState();
}

class _ScanInvitePageState extends State<ScanInvitePage> {
  final GlobalKey _qrKey = GlobalKey();
  QRViewController? _qrController;

  /// On creation of QR view
  void _onQRViewCreated(QRViewController controller) {
    _qrController = controller;
    controller.scannedDataStream.listen((scanData) {
      // Try to decode invite
      try {
        Map<String, dynamic> inviteMap =
            jsonDecode(scanData.code!) as Map<String, dynamic>;
        InviteData invite = InviteData.fromJson(inviteMap);
        // Check if invite expired
        if (invite.validUntil.difference(DateTime.now()).isNegative) {
          Fluttertoast.showToast(
            msg: 'inviteExpired'.tr(),
            backgroundColor: Colors.red);
        } else {
          // Push registration page
        Navigator.pushReplacement(context,
            MaterialPageRoute(builder: (context) => RegisterPage(invite)));
        return;
        }
      } catch (e) {
        Fluttertoast.showToast(
            msg: 'invalidQr'.tr(),
            backgroundColor: Colors.red);
      }
    });
  }

  @override
  void dispose() {
    _qrController?.dispose();
    super.dispose();
  }

  @override
  void reassemble() {
    super.reassemble();
    if (_qrController != null) {
      _qrController!.pauseCamera();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                flex: 15,
                child: QRView(
                  overlay: QrScannerOverlayShape(
                    borderColor: Theme.of(context).colorScheme.secondary,
                    borderRadius: 10,
                    borderLength: 30,
                    borderWidth: 10,
                    cutOutSize: MediaQuery.of(context).size.width * 0.8,
                  ),
                  key: _qrKey,
                  onQRViewCreated: _onQRViewCreated,
                  formatsAllowed: [BarcodeFormat.qrcode],
                ),
              ),
              Expanded(
                flex: 1,
                child: Center(
                  child: Text('scanQr'.tr()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
