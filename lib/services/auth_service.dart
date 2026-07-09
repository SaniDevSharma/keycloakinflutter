import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../config/keycloak_config.dart';
import '../screens/login_webview_screen.dart';
import 'dpop_service.dart';
import 'secure_storage_service.dart';

/// Holds decoded information about the authenticated user.
class UserInfo {
  const UserInfo({
    required this.sub,
    required this.name,
    required this.email,
    required this.preferredUsername,
    this.givenName,
    this.familyName,
  });

  final String sub;
  final String name;
  final String email;
  final String preferredUsername;
  final String? givenName;
  final String? familyName;

  factory UserInfo.fromJson(Map<String, dynamic> json) => UserInfo(
        sub: json['sub'] as String? ?? '',
        name: json['name'] as String? ??
            json['preferred_username'] as String? ??
            'User',
        email: json['email'] as String? ?? '',
        preferredUsername: json['preferred_username'] as String? ?? '',
        givenName: json['given_name'] as String?,
        familyName: json['family_name'] as String?,
      );
}

/// Service that manages the full Keycloak OAuth2 / OIDC lifecycle:
///  • Authorization Code + PKCE via in-app webview
///  • Manual token exchange with DPoP proof header
///  • Token refresh with fresh DPoP proof
///  • Logout / session end
class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';
  static const _idTokenKey = 'id_token';

  // ──────────────────────────────────────────
  // Public API
  // ──────────────────────────────────────────

  /// Returns true if a (possibly stale) access token is in secure storage.
  Future<bool> get isLoggedIn async {
    final token = await SecureStorageService.instance.read(_accessTokenKey);
    return token != null && token.isNotEmpty;
  }

  /// Loads the stored access token (may be expired).
  Future<String?> get storedAccessToken =>
      SecureStorageService.instance.read(_accessTokenKey);

  /// Performs the full Authorization Code + PKCE + DPoP login using in-app Webview.
  Future<UserInfo> login(BuildContext context) async {
    // Generate PKCE values manually
    final codeVerifier = _generateCodeVerifier();
    final codeChallenge = _generateCodeChallenge(codeVerifier);
    final state = _generateState();

    // Construct authorization URL
    final authUrl = Uri.parse(KeycloakConfig.authorizationEndpoint).replace(
      queryParameters: {
        'response_type': 'code',
        'client_id': KeycloakConfig.clientId,
        'redirect_uri': KeycloakConfig.redirectUri,
        'scope': KeycloakConfig.scopes.join(' '),
        'state': state,
        'code_challenge': codeChallenge,
        'code_challenge_method': 'S256',
      },
    ).toString();

    // Launch webview and wait for result
    final result = await Navigator.of(context).push<Map<String, String?>>(
      MaterialPageRoute(
        builder: (context) => LoginWebviewScreen(
          authUrl: authUrl,
          redirectUri: KeycloakConfig.redirectUri,
        ),
      ),
    );

    if (result == null) {
      throw Exception('User cancelled flow');
    }

    if (result['error'] != null) {
      throw Exception(result['error_description'] ?? result['error']);
    }

    final code = result['code'];
    if (code == null) {
      throw Exception('No authorization code returned from login.');
    }

    // Step 2 – manual token exchange with DPoP proof
    final dpopProof = DpopService.instance.buildDpopProof(
      'POST',
      KeycloakConfig.tokenEndpoint,
    );

    final response = await http.post(
      Uri.parse(KeycloakConfig.tokenEndpoint),
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'DPoP': dpopProof,
      },
      body: {
        'grant_type': 'authorization_code',
        'client_id': KeycloakConfig.clientId,
        'code': code,
        'redirect_uri': KeycloakConfig.redirectUri,
        'code_verifier': codeVerifier,
      },
    );

    if (response.statusCode != 200) {
      final body = response.body;
      // Handle Keycloak's DPoP nonce challenge (use_dpop_nonce)
      if (response.statusCode == 400) {
        final json = jsonDecode(body) as Map<String, dynamic>;
        final error = json['error'] as String? ?? '';
        if (error == 'use_dpop_nonce') {
          final nonce = response.headers['dpop-nonce'];
          if (nonce != null) {
            return _retryTokenExchangeWithNonce(
              authCode: code,
              codeVerifier: codeVerifier,
              nonce: nonce,
            );
          }
        }
      }
      throw Exception('Token exchange failed (${response.statusCode}): $body');
    }

    final tokenData = jsonDecode(response.body) as Map<String, dynamic>;
    await _storeTokens(tokenData);
    return _fetchUserInfo(tokenData['access_token'] as String);
  }

  /// Retries the token exchange including a Keycloak-provided DPoP nonce.
  Future<UserInfo> _retryTokenExchangeWithNonce({
    required String authCode,
    required String codeVerifier,
    required String nonce,
  }) async {
    final dpopProof = DpopService.instance.buildDpopProof(
      'POST',
      KeycloakConfig.tokenEndpoint,
      nonce: nonce,
    );

    final response = await http.post(
      Uri.parse(KeycloakConfig.tokenEndpoint),
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'DPoP': dpopProof,
      },
      body: {
        'grant_type': 'authorization_code',
        'client_id': KeycloakConfig.clientId,
        'code': authCode,
        'redirect_uri': KeycloakConfig.redirectUri,
        'code_verifier': codeVerifier,
      },
    );

    if (response.statusCode != 200) {
      throw Exception(
          'Token exchange with nonce failed (${response.statusCode}): '
          '${response.body}');
    }

    final tokenData = jsonDecode(response.body) as Map<String, dynamic>;
    await _storeTokens(tokenData);
    return _fetchUserInfo(tokenData['access_token'] as String);
  }

  /// Silently refreshes the access token using the stored refresh token.
  Future<UserInfo> refreshToken() async {
    final storedRefresh =
        await SecureStorageService.instance.read(_refreshTokenKey);
    if (storedRefresh == null) {
      throw Exception('No refresh token stored.');
    }

    final dpopProof = DpopService.instance.buildDpopProof(
      'POST',
      KeycloakConfig.tokenEndpoint,
    );

    final response = await http.post(
      Uri.parse(KeycloakConfig.tokenEndpoint),
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'DPoP': dpopProof,
      },
      body: {
        'grant_type': 'refresh_token',
        'client_id': KeycloakConfig.clientId,
        'refresh_token': storedRefresh,
      },
    );

    if (response.statusCode != 200) {
      await logout();
      throw Exception('Token refresh failed — please log in again.');
    }

    final tokenData = jsonDecode(response.body) as Map<String, dynamic>;
    await _storeTokens(tokenData);
    return _fetchUserInfo(tokenData['access_token'] as String);
  }

  /// Ends the Keycloak session and clears local token storage.
  Future<void> logout() async {
    final idToken = await SecureStorageService.instance.read(_idTokenKey);

    if (idToken != null) {
      try {
        final logoutUrl = Uri.parse(KeycloakConfig.endSessionEndpoint).replace(
          queryParameters: {
            'id_token_hint': idToken,
            'post_logout_redirect_uri': KeycloakConfig.redirectUri,
          },
        );
        // Best effort background GET to notify server
        await http.get(logoutUrl).timeout(const Duration(seconds: 3));
      } catch (_) {}
    }

    await SecureStorageService.instance.delete(_accessTokenKey);
    await SecureStorageService.instance.delete(_refreshTokenKey);
    await SecureStorageService.instance.delete(_idTokenKey);
  }

  // ──────────────────────────────────────────
  // Private helpers
  // ──────────────────────────────────────────

  /// Generates a cryptographically secure PKCE code verifier (RFC 7636).
  String _generateCodeVerifier() {
    final random = Random.secure();
    final values = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Url.encode(values).replaceAll('=', '');
  }

  /// Generates a PKCE code challenge S256 (RFC 7636).
  String _generateCodeChallenge(String verifier) {
    final bytes = utf8.encode(verifier);
    final digest = sha256.convert(bytes);
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }

  /// Generates a random state string.
  String _generateState() {
    final random = Random.secure();
    final values = List<int>.generate(16, (_) => random.nextInt(256));
    return base64Url.encode(values).replaceAll('=', '');
  }

  Future<void> _storeTokens(Map<String, dynamic> tokenData) async {
    final store = SecureStorageService.instance;
    if (tokenData['access_token'] != null) {
      await store.write(_accessTokenKey, tokenData['access_token'] as String);
    }
    if (tokenData['refresh_token'] != null) {
      await store.write(
          _refreshTokenKey, tokenData['refresh_token'] as String);
    }
    if (tokenData['id_token'] != null) {
      await store.write(_idTokenKey, tokenData['id_token'] as String);
    }
  }

  /// Fetches user info from Keycloak's /userinfo endpoint with DPoP binding.
  Future<UserInfo> _fetchUserInfo(String accessToken) async {
    final dpopProof = DpopService.instance.buildDpopProof(
      'GET',
      KeycloakConfig.userinfoEndpoint,
      accessToken: accessToken,
    );

    final response = await http.get(
      Uri.parse(KeycloakConfig.userinfoEndpoint),
      headers: {
        'Authorization': 'DPoP $accessToken',
        'DPoP': dpopProof,
      },
    );

    if (response.statusCode == 200) {
      return UserInfo.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>);
    }

    // Fallback: decode claims from the access token itself.
    return _parseTokenClaims(accessToken);
  }

  /// Decodes JWT payload without signature verification.
  UserInfo _parseTokenClaims(String token) {
    final parts = token.split('.');
    if (parts.length < 2) {
      return const UserInfo(
        sub: '',
        name: 'User',
        email: '',
        preferredUsername: '',
      );
    }
    final payload = parts[1];
    final padded =
        payload.padRight(payload.length + (4 - payload.length % 4) % 4, '=');
    final decoded = utf8.decode(base64Url.decode(padded));
    return UserInfo.fromJson(jsonDecode(decoded) as Map<String, dynamic>);
  }
}
