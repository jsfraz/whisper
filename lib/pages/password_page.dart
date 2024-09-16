import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../utils/cache.dart';
import '../utils/singleton.dart';
import '../utils/utils.dart';

import 'home_page.dart';
import 'login_page.dart';

class PasswordPage extends StatefulWidget {
  const PasswordPage({super.key});

  @override
  State<PasswordPage> createState() => _PasswordPageState();
}

class _PasswordPageState extends State<PasswordPage> {
  final _controllerPassword = TextEditingController();
  bool _passwordEditing = false;
  bool _passwordOk = false;
  bool _isButtonDisabled = false;
  bool _emptyPasswordHash = false;

  @override
  void initState() {
    super.initState();
    // Check if password hash is null and show message
    Cache.getPasswordHash().then((passwordHash) {
      // New data message
      if (passwordHash == null) {
        _emptyPasswordHash = true;
        /*
        Utils.showText(
            'newData'.tr(), Theme.of(context).colorScheme.secondary, context);
        */
      } else {
        /*
        // Existing data message
        Utils.showText('existingData'.tr(),
            Theme.of(context).colorScheme.secondary, context);
        */
      }
    });
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

  /// Save password
  Future<void> _password() async {
    // Disable button
    setState(() {
      _isButtonDisabled = true;
    });

    /*
    // Check input
    if (_passwordOk) {
      // New data
      if (_emptyPasswordHash) {
        // Add key to singleton
        Singleton().boxCollectionKey =
            await CryptoUtils.pbkdf2(_controllerPassword.text);
        // Save password hash to cache
        Cache.setPasswordHash(_controllerPassword.text);
        // Save profile to cache
        await Cache.setProfile(Singleton().profile);
        // Redirect to home page
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (context) => const HomePage()));
      } else {
        // Existing data
        bool password = await Cache.isCorrectPassword(_controllerPassword.text);
        // Check password
        if (password) {
          // Add key to singleton
          Singleton().boxCollectionKey =
              await CryptoUtils.pbkdf2(_controllerPassword.text);
          // Add profile to singleton
          Singleton().profile = await Cache.getProfile();
          // Redirect to password page
          Navigator.pushReplacement(context,
              MaterialPageRoute(builder: (context) => const HomePage()));
        } else {
          Utils.showText('invalidPassword'.tr(),
              Theme.of(context).colorScheme.error, context);
        }
      }
    }
    */

    // Enable button
    setState(() {
      _isButtonDisabled = false;
    });
  }

  @override
  void dispose() {
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
                      onPressed: _password,
                      child: Padding(
                        padding: const EdgeInsets.all(7),
                        child: Text(
                          'passwordButton'.tr(),
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
                                  builder: (context) => const LoginPage('')));
                        }
                      },
                      child: Text('useDifferentAcc'.tr()),
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
