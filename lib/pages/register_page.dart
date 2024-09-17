import 'dart:async';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:whisper/models/invite.dart';
import 'package:whisper/models/profile.dart';
import '../models/user.dart';
import 'package:whisper_openapi_client/api.dart';
import '../utils/crypto_utils.dart';
import '../utils/singleton.dart';
import '../utils/utils.dart';
import 'package:basic_utils/basic_utils.dart' as bu;

import 'password_page.dart';

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

      // TODO password field here instead of password page
      if (_usernameOk) {
        // Toast and async sleep before heavy computation
        Fluttertoast.showToast(
            msg: 'waitPls'.tr(), backgroundColor: Colors.grey);
        // Generate RSA keypair
        var keyPair = await CryptoUtils.getRSAKeyPair();
        // OpenAPI client
        Singleton().api = ApiClient(basePath: widget.invite.url);
        // Registration
        var newUser = await Utils.callApi(() => Singleton().userApi.createUser(
            createUserInput: CreateUserInput(
                inviteCode: widget.invite.code,
                publicKey: bu.CryptoUtils.encodeRSAPublicKeyToPem(
                    keyPair.publicKey as bu.RSAPublicKey),
                username: _controllerUsername.text)));
        if (newUser != null) {
          // Create profile
          Profile profile = Profile(widget.invite.url, User.fromModel(newUser));
          // Add profile to singleton
          Singleton().profile = profile;
          // Redirect to password page
          Navigator.pushReplacement(context,
              MaterialPageRoute(builder: (context) => const PasswordPage()));
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
