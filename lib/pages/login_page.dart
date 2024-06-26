import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../models/user.dart';
import 'package:whisper_openapi_client/api.dart';
import '../models/profile.dart';
import '../utils/cache.dart';
import '../utils/is_response_ok.dart';
import '../utils/singleton.dart';
import '../utils/utils.dart';
import 'password_page.dart';
import 'register_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage(this.basePath, {super.key});
  final String basePath;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

// https://codewithandrea.com/articles/flutter-text-field-form-validation/
class _LoginPageState extends State<LoginPage> {
  final _controllerServer = TextEditingController();
  bool _serverEditing = false;
  bool _serverOk = false;
  final _controllerUsername = TextEditingController();
  bool _usernameEditing = false;
  bool _usernameOk = false;
  final _controllerPassword = TextEditingController();
  bool _passwordEditing = false;
  bool _passwordOk = false;
  bool _forceHttps = true;
  bool _isButtonDisabled = false;
  bool _emptyPasswordHash = false;

  @override
  void initState() {
    super.initState();
    if (widget.basePath.isNotEmpty) {
      _serverOk = true;
    }
    // Check if password hash is null and show message
    Cache.getPasswordHash().then((passwordHash) {
      // New data message
      if (passwordHash == null) {
        _emptyPasswordHash = true;
      }
    });
  }

  /// Check server address
  String? _errorServerText() {
    if (!_serverEditing) {
      return null;
    }
    if (_controllerServer.text.isNotEmpty) {
      _serverOk = true;
      return null;
    } else {
      _serverOk = false;
      return 'invalidServer'.tr();
    }
  }

  /// Check username
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

  /// Check password
  String? _errorPasswordText() {
    if (!_passwordEditing) {
      return null;
    }
    if (_controllerPassword.text.length >= 8 &&
        _controllerPassword.text.length <= 64) {
      _passwordOk = true;
      return null;
    } else {
      _passwordOk = false;
      return 'invalidPassword'.tr();
    }
  }

  /// Login button
  Future<void> _login() async {
    if (!_isButtonDisabled) {
      // Disable button
      setState(() {
        _isButtonDisabled = true;
      });

      // Check input
      if (_serverOk && _usernameOk && _passwordOk) {
        // HTTPS option
        String path = '';
        if (widget.basePath.isEmpty) {
          if (_forceHttps) {
            path = 'https://${_controllerServer.text}';
          } else {
            path = 'http://${_controllerServer.text}';
          }
        } else {
          path = widget.basePath;
        }

        // OpenAPI client
        Singleton().api = ApiClient(basePath: path);
        // Verify
        var response = await Utils.callApi(
            () => Singleton().authApi.loginUserWithHttpInfo(
                loginUserInput: LoginUserInput(
                    password: _controllerPassword.text,
                    username: _controllerUsername.text)),
            context);
        // Response check
        if (response?.ok ?? false) {
          /*
          Utils.showText('successfulLogin'.tr(),
              Theme.of(context).colorScheme.secondary, context);
          */

          // Delete cache
          if (!_emptyPasswordHash) {
            await Cache.deleteCache();
          }

          // Response from JSON
          ModelsAuthResponse? authResponse =
              ModelsAuthResponse.fromJson(jsonDecode(response!.body));
          // Create profile instance
          Profile profile = Profile(
              path,
              authResponse!.accessToken,
              authResponse.refreshToken,
              User.fromModelsUser(authResponse.user),
              _controllerPassword.text);
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
    _controllerServer.dispose();
    _controllerUsername.dispose();
    _controllerPassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvoked: (didPop) {
        if (didPop) {
          !_isButtonDisabled;
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
            automaticallyImplyLeading: false,
            leading: !Utils.isPhone()
                ? BackButton(onPressed: () => Navigator.pop(context))
                : null),
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Visibility(
                  visible: widget.basePath.isEmpty,
                  child: SizedBox(
                    width: 300,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 15),
                      child: TextField(
                        enabled: !_isButtonDisabled,
                        controller: _controllerServer,
                        onChanged: (_) => setState(() {
                          _serverEditing = true;
                        }),
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          labelText: 'serverPlaceholder'.tr(),
                          errorText: _errorServerText(),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 300,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 15),
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
                ),
                SizedBox(
                  width: 300,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 15),
                    child: TextField(
                      enabled: !_isButtonDisabled,
                      obscureText: true,
                      controller: _controllerPassword,
                      onChanged: (_) => setState(() {
                        _passwordEditing = true;
                      }),
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        labelText: 'passwordPlaceholder'.tr(),
                        errorText: _errorPasswordText(),
                      ),
                    ),
                  ),
                ),
                Visibility(
                  visible: widget.basePath.isEmpty,
                  child: SizedBox(
                    width: 300,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 15),
                      child: Row(children: [
                        Column(
                          children: [
                            Switch(
                                value: _forceHttps,
                                onChanged: (bool value) {
                                  setState(() {
                                    if (!_isButtonDisabled) {
                                      _forceHttps = !_forceHttps;
                                    }
                                  });
                                }),
                          ],
                        ),
                        Column(children: [
                          Padding(
                            padding: const EdgeInsets.only(left: 10),
                            child: Text(
                              'forceHttps'.tr(),
                              style: const TextStyle(fontSize: 15),
                            ),
                          ),
                        ])
                      ]),
                    ),
                  ),
                ),
                Visibility(
                  visible: !_isButtonDisabled,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 20, left: 7, right: 7),
                    child: TextButton(
                      style: ButtonStyle(
                        backgroundColor: WidgetStateProperty.all(
                            Theme.of(context).colorScheme.primary),
                        shape: WidgetStateProperty.all<RoundedRectangleBorder>(
                          RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(35)),
                        ),
                      ),
                      onPressed: _login,
                      child: Padding(
                        padding: const EdgeInsets.all(7),
                        child: Text(
                          'loginButton'.tr(),
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.surface,
                              fontSize: 20),
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
                Visibility(
                  visible: !_emptyPasswordHash,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 25),
                    child: TextButton(
                      onPressed: () {
                        if (_isButtonDisabled == false) {
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => const RegisterPage()));
                        }
                      },
                      child: Text('createNewAcc'.tr()),
                    ),
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}
