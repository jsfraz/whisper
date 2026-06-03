import 'dart:async';
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
  StreamSubscription<Barcode>? _scanSubscription;
  bool _isProcessingScan = false;
  final Set<String> _shownToastForScan = {};

  /// On creation of QR view
  void _onQRViewCreated(QRViewController controller) {
    _qrController = controller;
    _scanSubscription?.cancel();
    _scanSubscription = controller.scannedDataStream.listen(_onScan);
  }

  bool _showScanToastOnce(String scanCode, String toastKey) {
    if (!_shownToastForScan.add('$toastKey:$scanCode')) {
      return false;
    }
    return true;
  }

  Future<void> _onScan(Barcode scanData) async {
    if (_isProcessingScan || !mounted) return;
    final scanCode = scanData.code;
    if (scanCode == null) return;

    try {
      final inviteMap = jsonDecode(scanCode) as Map<String, dynamic>;
      final invite = InviteData.fromJson(inviteMap);
      if (invite.validUntil.difference(DateTime.now()).isNegative) {
        if (_showScanToastOnce(scanCode, 'inviteExpired')) {
          Fluttertoast.showToast(
            msg: 'inviteExpired'.tr(),
            backgroundColor: Colors.red,
          );
        }
        return;
      }

      _isProcessingScan = true;
      await _qrController?.pauseCamera();
      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => RegisterPage(invite)),
      );
    } catch (_) {
      if (_showScanToastOnce(scanCode, 'invalidQr')) {
        Fluttertoast.showToast(
          msg: 'invalidQr'.tr(),
          backgroundColor: Colors.red,
        );
      }
    } finally {
      if (_isProcessingScan) {
        _isProcessingScan = false;
        if (mounted) {
          await _qrController?.resumeCamera();
        }
      }
    }
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
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
