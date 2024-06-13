import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:whisper/utils/is_response_ok.dart';
import 'package:whisper_openapi_client/api.dart';

import '../utils/http_utils.dart';
import '../utils/singleton.dart';
import '../utils/ui_utils.dart';
import '../utils/utils.dart';

class VerifyPage extends StatefulWidget {
  final String basePath;

  const VerifyPage(this.basePath, {super.key});

  @override
  State<VerifyPage> createState() => _VerifyPageState();
}

class _VerifyPageState extends State<VerifyPage> {
  final _controllerServer = TextEditingController();
  bool _serverEditing = false;
  bool _serverOk = false;
  final _controllerCode = TextEditingController();
  bool _codeEditing = false;
  bool _codeOk = false;
  bool _forceHttps = true;
  bool _isButtonDisabled = false;

  @override
  void initState() {
    if (widget.basePath.isNotEmpty) {
      _serverOk = true;
    }
    super.initState();
  }

  // Check server address
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

  // Check username
  String? _errorCodeText() {
    if (!_codeEditing) {
      return null;
    }
    if (_controllerCode.text.length == 32) {
      _codeOk = true;
      return null;
    } else {
      _codeOk = false;
      return 'invalidCode'.tr();
    }
  }

  // Verify button
  Future<void> _verify() async {
    // disable button
    setState(() {
      _isButtonDisabled = true;
    });

    // Check input
    if (_serverOk && _codeOk) {
      // OpenAPI client
      Singleton().api = ApiClient(basePath: widget.basePath);
      // Verify
      var response = await HttpUtils.callApi(
          () => Singleton().authApi.verifyUserWithHttpInfo(
              verifyUserInput: VerifyUserInput(code: _controllerCode.text)),
          context);
      // Response check
      if (response?.ok ?? false) {
        UiUtils.showText('accountVerified'.tr(),
            Theme.of(context).colorScheme.secondary, context);
        // TODO login page
        /*
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (context) => LoginPage(url)));
        */
      }
    }

    // Enable button
    setState(() {
      _isButtonDisabled = false;
    });
  }

  @override
  void dispose() {
    _controllerServer.dispose();
    _controllerCode.dispose();
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
                Visibility(
                  visible: widget.basePath.isNotEmpty,
                  child: Padding(
                    padding: const EdgeInsets.only(
                      top: 10,
                    ),
                    child: SizedBox(
                      width: 400,
                      child: Text(
                        'codeMail'.tr(),
                        textAlign: TextAlign.center,
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
                      controller: _controllerCode,
                      onChanged: (_) => setState(() {
                        _codeEditing = true;
                      }),
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        labelText: 'codePlaceholder'.tr(),
                        errorText: _errorCodeText(),
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
                      onPressed: _verify,
                      child: Padding(
                        padding: const EdgeInsets.all(7),
                        child: Text(
                          'verifyButton'.tr(),
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
                  child: const CircularProgressIndicator(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}