/// Keycloak configuration constants.
/// Update these values to match your Keycloak deployment.
class KeycloakConfig {
  KeycloakConfig._();

  static const String baseUrl = 'http://192.168.1.41:8080';
  static const String realm = 'TestSSO';
  static const String clientId = 'app-one';

  /// Custom scheme redirect URI registered in Keycloak → app-one → Valid Redirect URIs
  static const String redirectUri =
      'com.example.mobileappwithkeycloak://oauthredirect';

  static const List<String> scopes = ['openid', 'profile', 'email'];

  // ----- Derived URLs -----
  static String get realmBase =>
      '$baseUrl/realms/$realm/protocol/openid-connect';

  static String get authorizationEndpoint => '$realmBase/auth';
  static String get tokenEndpoint => '$realmBase/token';
  static String get endSessionEndpoint => '$realmBase/logout';
  static String get userinfoEndpoint => '$realmBase/userinfo';
}
