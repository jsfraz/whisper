import 'package:http/http.dart';

/// https://stackoverflow.com/a/70282800/19371130
extension IsResponseOk on Response {
  bool get ok {
    return (statusCode ~/ 100) == 2;
  }
}
