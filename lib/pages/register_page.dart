import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:whisper/models/invite.dart';
import '../utils/is_response_ok.dart';
import 'package:whisper_openapi_client/api.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../utils/rsa_utils.dart';
import '../utils/singleton.dart';
import '../utils/utils.dart';
import 'login_page.dart';
import 'verify_page.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:basic_utils/basic_utils.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage(this.invite, {super.key});

  final Invite invite;

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  // https://codewithandrea.com/articles/flutter-text-field-form-validation/
  final _controllerUsername = TextEditingController();
  bool _usernameEditing = false;
  bool _usernameOk = false;
  late Timer _timer;
  late Duration _remainingTime;
  bool _isButtonDisabled = false;

  @override
  void initState() {
    super.initState();
    _remainingTime = widget.invite.validUntil.difference(DateTime.now());

    // Start the timer to update every second
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _remainingTime = widget.invite.validUntil.difference(DateTime.now());
      });
    });
  }

  /// Check username.
  String? _errorUsernameText() {
    if (!_usernameEditing) {
      return null;
    }
    RegExp regex = RegExp(r"^[a-zA-Z0-9]{2,32}$");
    if (regex.hasMatch(_controllerUsername.text)) {
      _usernameOk = true;
      return null;
    } else {
      _usernameOk = false;
      return 'invalidUsername'.tr();
    }
  }

  /// Register button action.
  Future<void> _register() async {
    if (!_isButtonDisabled) {
      // Disable button
      setState(() {
        _isButtonDisabled = true;
      });

      /*
      // Check input
      if (_serverOk &&
          _usernameOk &&
          _mailOk &&
          _passwordOk &&
          _passwordRepeatOk) {
        // HTTPS option
        String url = '';
        if (_forceHttps) {
          url = 'https://${_controllerServer.text}';
        } else {
          url = 'http://${_controllerServer.text}';
        }

        // OpenAPI client
        Singleton().api = ApiClient(basePath: url);
        // Registration
        var response = await Utils.callApi(
            () => Singleton().authApi.registerUserWithHttpInfo(
                registerUserInput: RegisterUserInput(
                    mail: _controllerMail.text,
                    password: _controllerPassword.text,
                    username: _controllerUsername.text)),
            context);
        // Response check
        if (response?.ok ?? false) {
          _clearInput();
          Navigator.push(context,
              MaterialPageRoute(builder: (context) => VerifyPage(url)));
        }
      }
      */

      if (_usernameOk) {
        // Toast and async sleep before heavy computation
        Fluttertoast.showToast(msg: 'waitPls', backgroundColor: Colors.grey);
        // Generate RSA keypair
        var keyPair = await RsaUtils.getRSAKeyPair();
        debugPrint(CryptoUtils.encodeRSAPublicKeyToPem(
            keyPair.publicKey as RSAPublicKey));
        // OpenAPI client
        Singleton().api = ApiClient(basePath: widget.invite.url);
        // Registration
        var response = await Utils.callApi(() => Singleton()
            .userApi
            .createUserWithHttpInfo(
                createUserInput: CreateUserInput(
                    inviteCode: widget.invite.code,
                    publicKey: CryptoUtils.encodeRSAPublicKeyToPem(
                        keyPair.publicKey as RSAPublicKey),
                    username: _controllerUsername.text)));
        // Response check
        if (response?.ok ?? false) {
          // TODO Save profile
          // TODO Push home page
        }
      }

      // Enable button
      setState(() {
        _isButtonDisabled = false;
      });
    }
  }

  @override
  void dispose() {
    _controllerUsername.dispose();
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Stop when remaining time is negative
    if (_remainingTime.isNegative) {
      _timer.cancel();
    }
    // Calculate absolute remaining time
    Duration displayDuration = _remainingTime;
    // Format display time
    String displayTime =
        displayDuration.toString().split('.').first.padLeft(8, '0');

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          !_isButtonDisabled;
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 300,
                  child: TextField(
                    enabled: !_isButtonDisabled,
                    controller: _controllerUsername,
                    onChanged: (_) => setState(() {
                      _usernameEditing = true;
                    }),
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: 'usernamePlaceholder'.tr(),
                      errorText: _errorUsernameText(),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 15),
                  child: Text(
                    _remainingTime.isNegative
                        ? 'inviteExpired'.tr()
                        : '${'inviteValidFor'.tr()}: $displayTime',
                    style: TextStyle(
                      color: _remainingTime.isNegative
                          ? Colors.red
                          : Theme.of(context).colorScheme.secondary,
                      fontWeight: _remainingTime.isNegative
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ),
                Visibility(
                  visible: !_isButtonDisabled,
                  child: Padding(
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
                      onPressed: _register,
                      child: Padding(
                        padding: const EdgeInsets.all(7),
                        child: Text(
                          'registerButton'.tr(),
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.surface,
                              fontSize: 16),
                        ),
                      ),
                    ),
                  ),
                ),
                Visibility(
                  visible: _isButtonDisabled,
                  child: const Padding(
                    padding: EdgeInsets.only(top: 20, left: 7, right: 7),
                    child: CircularProgressIndicator(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
