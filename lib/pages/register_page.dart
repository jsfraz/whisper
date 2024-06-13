import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:whisper/utils/is_response_ok.dart';
import 'package:whisper_openapi_client/api.dart';

import '../utils/http_utils.dart';
import '../utils/singleton.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  // https://codewithandrea.com/articles/flutter-text-field-form-validation/
  final _controllerServer = TextEditingController();
  bool _serverEditing = false;
  bool _serverOk = false;
  final _controllerUsername = TextEditingController();
  bool _usernameEditing = false;
  bool _usernameOk = false;
  final _controllerMail = TextEditingController();
  bool _mailEditing = false;
  bool _mailOk = false;
  final _controllerPassword = TextEditingController();
  bool _passwordEditing = false;
  bool _passwordOk = false;
  final _controllerPasswordRepeat = TextEditingController();
  bool _passwordRepeatEditing = false;
  bool _passwordRepeatOk = false;
  bool _forceHttps = true;
  bool _isButtonDisabled = false;

  // Check server address.
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

  /// Check mail.
  String? _errorMailText() {
    if (!_mailEditing) {
      return null;
    }
    // https://regexr.com/3e48o
    RegExp regex = RegExp(r"^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$");
    if (regex.hasMatch(_controllerMail.text)) {
      _mailOk = true;
      return null;
    } else {
      _mailOk = false;
      return 'invalidMail'.tr();
    }
  }

  /// Check password.
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

  /// Check repeated password.
  String? _errorPasswordRepeatText() {
    if (!_passwordRepeatEditing) {
      return null;
    }
    if (_controllerPasswordRepeat.text.length >= 8 &&
        _controllerPasswordRepeat.text.length <= 64 &&
        _controllerPassword.text == _controllerPasswordRepeat.text &&
        _controllerPasswordRepeat.text.isNotEmpty) {
      _passwordRepeatOk = true;
      return null;
    } else {
      _passwordRepeatOk = false;
      return 'invalidPasswordRepeat'.tr();
    }
  }

  /// Register button action.
  Future<void> _register() async {
    if (!_isButtonDisabled) {
      // Disable button
      setState(() {
        _isButtonDisabled = true;
      });

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
        // Registartion
        var response = await HttpUtils.callApi(
            () => Singleton().authApi.registerUserWithHttpInfo(
                registerUserInput: RegisterUserInput(
                    mail: _controllerMail.text,
                    password: _controllerPassword.text,
                    username: _controllerUsername.text)),
            context);
        // Response check
        if (response!.ok) {
          _clearInput();
          // TODO verification page
          /*
            Navigator.push(context,
                MaterialPageRoute(builder: (context) => VerifyPage(url)));
            */
        }
      }

      // Enable button
      setState(() {
        _isButtonDisabled = false;
      });
    }
  }

  /// Clears user input.
  _clearInput() {
    setState(() {
      _controllerServer.clear();
      _serverEditing = false;
      _serverOk = false;
      _controllerUsername.clear();
      _usernameEditing = false;
      _usernameOk = false;
      _controllerMail.clear();
      _mailEditing = false;
      _mailOk = false;
      _controllerPassword.clear();
      _passwordEditing = false;
      _passwordOk = false;
      _controllerPasswordRepeat.clear();
      _passwordRepeatEditing = false;
      _passwordEditing = false;
      _forceHttps = true;
    });
  }

  @override
  void dispose() {
    _controllerServer.dispose();
    _controllerUsername.dispose();
    _controllerMail.dispose();
    _controllerPassword.dispose();
    _controllerPasswordRepeat.dispose();
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
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                SizedBox(
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
                      controller: _controllerMail,
                      onChanged: (_) => setState(() {
                        _mailEditing = true;
                      }),
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        labelText: 'mailPlaceholder'.tr(),
                        errorText: _errorMailText(),
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
                SizedBox(
                  width: 300,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 15),
                    child: TextField(
                      enabled: !_isButtonDisabled,
                      obscureText: true,
                      controller: _controllerPasswordRepeat,
                      onChanged: (_) => setState(() {
                        _passwordRepeatEditing = true;
                      }),
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        labelText: 'passwordRepeatPlaceholder'.tr(),
                        errorText: _errorPasswordRepeatText(),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 300,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 15, bottom: 20),
                    child: Row(
                      children: [
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
                        Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(left: 10),
                              child: Text(
                                'forceHttps'.tr(),
                                style: const TextStyle(fontSize: 15),
                              ),
                            ),
                          ],
                        )
                      ],
                    ),
                  ),
                ),
                Visibility(
                  visible: !_isButtonDisabled,
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
                Visibility(
                  visible: _isButtonDisabled,
                  child: const CircularProgressIndicator(),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 25),
                  child: TextButton(
                    onPressed: () {
                      if (_isButtonDisabled == false) {
                        // TODO verify page
                        /*
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) => const VerifyPage('')));
                        */
                      }
                    },
                    child: Text('verifyMail'.tr()),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    if (_isButtonDisabled == false) {
                      // TODO login page
                      /*
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const LoginPage('')));
                      */
                    }
                  },
                  child: Text('haveAccount'.tr()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
