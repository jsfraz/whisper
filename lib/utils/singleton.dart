import 'package:whisper_openapi_client/api.dart';

import '../models/profile.dart';

/// Singleton https://stackoverflow.com/a/12649574/19371130
class Singleton {
  static final Singleton _singleton = Singleton._internal();

  // OpenAPI client instance
  late ApiClient _api;
  // User profile
  late Profile profile;
  // Box key
  late List<int> boxCollectionKey;

  factory Singleton() {
    return _singleton;
  }

  Singleton._internal();

  // Setters
  set api(ApiClient api) => _api = api;

  set apiToken(String token) {
    var auth = HttpBearerAuth();
    auth.accessToken = Singleton().profile.accessToken;
    _api = ApiClient(basePath: Singleton().profile.url, authentication: auth);
  }

  // Getters
  UserApi get userApi => UserApi(_api);
  
  AuthenticationApi get authApi => AuthenticationApi(_api);
}
