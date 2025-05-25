import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:whisper_openapi_client_dart/api.dart';
import 'package:whisper_websocket_client_dart/ws_client.dart';
import '../utils/cache_utils.dart';
import '../utils/crypto_utils.dart';
import '../utils/singleton.dart';
import '../utils/utils.dart';
import 'home_page.dart';

class PasswordPage extends StatefulWidget {
  const PasswordPage({super.key});

  @override
  State<PasswordPage> createState() => _PasswordPageState();
}

class _PasswordPageState extends State<PasswordPage> {
  final _controllerLocalPassword = TextEditingController();
  bool _localPasswordEditing = false;
  bool _localPasswordOk = false;
  bool _isButtonDisabled = false;

  /// Check password
  String? _errorLocalPasswordText() {
    if (!_localPasswordEditing) {
      return null;
    }
    if (_controllerLocalPassword.text.length >= 8 &&
        _controllerLocalPassword.text.length <= 64) {
      _localPasswordOk = true;
      return null;
    } else {
      _localPasswordOk = false;
      return 'invalidPassword'.tr();
    }
  }

  /// Save password
  Future<void> _localPassword() async {
    // Disable button
    setState(() {
      _isButtonDisabled = true;
    });

    // Check input
    if (_localPasswordOk) {
      // Existing data
      bool password = await CacheUtils.isCorrectPassword(_controllerLocalPassword.text);
      // Check password
      if (password) {
        Fluttertoast.showToast(
            msg: 'passwordPlsWait'.tr(),
            backgroundColor: Colors.grey);
        // Add key to singleton
        Singleton().boxCollectionKey =
            await CryptoUtils.pbkdf2(_controllerLocalPassword.text);
        // Add profile to singleton
        Singleton().profile = await CacheUtils.getProfile();

        // OpenAPI client
        Singleton().api = ApiClient(basePath: Singleton().profile.url);
        // TODO Check connection/ping
        // Check tokens
        await Utils.authCheck();
        // WebSocket client
        Singleton().wsClient = WsClient(Utils.getWsUrl(Singleton().profile.url), onReceived: Utils.onWsMessageReceived);
        await Utils.wsConnect(firstConnect: true);

        // Redirect to password page
        if (mounted) {
          Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (context) => const HomePage()));
        }
      } else {
        Fluttertoast.showToast(
            msg: 'invalidLocalPassword'.tr(),
            backgroundColor: Colors.red);
      }
    }
    // Enable button
    setState(() {
      _isButtonDisabled = false;
    });
  }

  @override
  void dispose() {
    _controllerLocalPassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
              children: <Widget>[
                SizedBox(
                  width: 300,
                  child: TextField(
                    enabled: !_isButtonDisabled,
                    obscureText: true,
                    controller: _controllerLocalPassword,
                    onChanged: (_) => setState(() {
                      _localPasswordEditing = true;
                    }),
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: 'localPasswordPlaceholder'.tr(),
                      errorText: _errorLocalPasswordText(),
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
                      onPressed: _localPassword,
                      child: Padding(
                        padding: const EdgeInsets.all(7),
                        child: Text(
                          'localPasswordButton'.tr(),
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
