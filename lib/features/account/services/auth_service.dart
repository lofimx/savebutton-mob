import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:kaya/core/services/logger_service.dart';
import 'package:kaya/features/account/services/account_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'auth_service.g.dart';

const _keyRefreshToken = 'kaya_refresh_token';
const _keyAccessToken = 'kaya_access_token';
const _keyAccessTokenExpiry = 'kaya_access_token_expiry';

/// Header to skip ngrok's browser warning interstitial during development.
const _ngrokHeaders = {'ngrok-skip-browser-warning': 'true'};

/// Authentication service for JWT-based auth with the Save Button server.
/// Handles PKCE code generation, token exchange, refresh, and storage.
class AuthService {
  final FlutterSecureStorage _secureStorage;
  final AccountRepository _accountRepo;
  final LoggerService? _logger;

  // In-memory cache of access token for performance
  String? _cachedAccessToken;
  DateTime? _cachedAccessTokenExpiry;

  // PKCE state for in-progress authorization
  String? _pendingCodeVerifier;

  AuthService(this._secureStorage, this._accountRepo, this._logger);

  /// Whether the user has a valid refresh token stored.
  Future<bool> hasTokenAuth() async {
    final refreshToken = await _secureStorage.read(key: _keyRefreshToken);
    return refreshToken != null && refreshToken.isNotEmpty;
  }

  /// Get a valid access token, refreshing if expired.
  /// Returns null if no auth is available.
  Future<String?> getAccessToken() async {
    // Check in-memory cache first
    if (_cachedAccessToken != null && _cachedAccessTokenExpiry != null) {
      // Leave a 60-second buffer before expiry
      if (_cachedAccessTokenExpiry!.isAfter(
        DateTime.now().add(const Duration(seconds: 60)),
      )) {
        return _cachedAccessToken;
      }
    }

    // Try to read from secure storage
    final storedToken = await _secureStorage.read(key: _keyAccessToken);
    final storedExpiry = await _secureStorage.read(key: _keyAccessTokenExpiry);
    if (storedToken != null && storedExpiry != null) {
      final expiry = DateTime.tryParse(storedExpiry);
      if (expiry != null &&
          expiry.isAfter(DateTime.now().add(const Duration(seconds: 60)))) {
        _cachedAccessToken = storedToken;
        _cachedAccessTokenExpiry = expiry;
        return storedToken;
      }
    }

    // Access token expired or missing -- try to refresh
    return await refreshAccessToken();
  }

  /// Refresh the access token using the stored refresh token.
  /// Returns the new access token, or null if refresh fails.
  Future<String?> refreshAccessToken() async {
    final refreshToken = await _secureStorage.read(key: _keyRefreshToken);
    if (refreshToken == null || refreshToken.isEmpty) {
      _logger?.d('Auth: no refresh token available');
      return null;
    }

    final serverUrl = _accountRepo.getServerUrl();
    final uri = Uri.parse('$serverUrl/api/v1/auth/token');

    try {
      final response = await http.post(uri, headers: _ngrokHeaders, body: {
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
      });

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final accessToken = json['access_token'] as String;
        final expiresIn = json['expires_in'] as int;

        await _storeAccessToken(accessToken, expiresIn);
        _logger?.i('Auth: access token refreshed');
        return accessToken;
      } else {
        _logger?.w(
          'Auth: refresh failed with status ${response.statusCode}',
        );
        // Refresh token is invalid -- clear all tokens
        await clearTokens();
        return null;
      }
    } catch (e) {
      _logger?.e('Auth: refresh failed', e);
      return null;
    }
  }

  /// Exchange email/password for JWT tokens (password grant).
  /// Returns the user email from the server response, or throws on failure.
  Future<String> authenticateWithPassword({
    required String email,
    required String password,
    required String deviceName,
    required String deviceType,
    String? appVersion,
  }) async {
    final serverUrl = _accountRepo.getServerUrl();
    final uri = Uri.parse('$serverUrl/api/v1/auth/token');

    final response = await http.post(uri, headers: _ngrokHeaders, body: {
      'grant_type': 'password',
      'email': email,
      'password': password,
      'device_name': deviceName,
      'device_type': deviceType,
      // ignore: use_null_aware_elements
      if (appVersion != null) 'app_version': appVersion,
    });

    if (response.statusCode == 201) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      await _storeTokens(json);
      final userEmail = json['user_email'] as String;
      _logger?.i('Auth: authenticated with password for $userEmail');
      return userEmail;
    } else {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final description =
          json['error_description'] as String? ?? json['error'] as String? ?? 'Authentication failed';
      throw AuthenticationException(description);
    }
  }

  /// Generate PKCE parameters for the authorization flow.
  /// Returns a map with code_challenge for the authorize URL.
  PkceParams generatePkceParams() {
    final verifier = _generateCodeVerifier();
    _pendingCodeVerifier = verifier;
    final challenge = _generateCodeChallenge(verifier);
    return PkceParams(codeChallenge: challenge, codeChallengeMethod: 'S256');
  }

  /// Build the authorization URL for opening in the browser.
  /// If [provider] is specified (e.g. 'google_oauth2', 'microsoft_graph'),
  /// opens a provider-specific login page. If [register] is true, opens the
  /// registration page. Otherwise opens the generic login page.
  Uri buildAuthorizeUrl({
    required String deviceName,
    required String deviceType,
    String? provider,
    bool register = false,
    String? state,
  }) {
    final pkce = generatePkceParams();
    final serverUrl = _accountRepo.getServerUrl();

    String path = '$serverUrl/api/v1/auth/authorize';
    if (register) {
      path = '$path/register';
    } else if (provider != null) {
      path = '$path/$provider';
    }

    return Uri.parse(path).replace(
      queryParameters: {
        'code_challenge': pkce.codeChallenge,
        'code_challenge_method': pkce.codeChallengeMethod,
        'redirect_uri': 'savebutton://auth/callback',
        'device_name': deviceName,
        'device_type': deviceType,
        // ignore: use_null_aware_elements
        if (state != null) 'state': state,
      },
    );
  }

  /// Exchange an authorization code for tokens (after browser callback).
  /// Returns the user email from the server response.
  Future<String> exchangeAuthorizationCode({
    required String code,
    required String deviceName,
    required String deviceType,
    String? appVersion,
  }) async {
    final codeVerifier = _pendingCodeVerifier;
    _pendingCodeVerifier = null;

    if (codeVerifier == null) {
      throw AuthenticationException('No pending PKCE verifier');
    }

    final serverUrl = _accountRepo.getServerUrl();
    final uri = Uri.parse('$serverUrl/api/v1/auth/token');

    final response = await http.post(uri, headers: _ngrokHeaders, body: {
      'grant_type': 'authorization_code',
      'code': code,
      'code_verifier': codeVerifier,
      'device_name': deviceName,
      'device_type': deviceType,
      // ignore: use_null_aware_elements
      if (appVersion != null) 'app_version': appVersion,
    });

    if (response.statusCode == 201) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      await _storeTokens(json);
      final userEmail = json['user_email'] as String;
      _logger?.i('Auth: authenticated via OAuth for $userEmail');
      return userEmail;
    } else {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final description =
          json['error_description'] as String? ?? json['error'] as String? ?? 'Token exchange failed';
      throw AuthenticationException(description);
    }
  }

  /// Revoke the refresh token and clear all stored tokens.
  Future<void> logout() async {
    final refreshToken = await _secureStorage.read(key: _keyRefreshToken);
    if (refreshToken != null && refreshToken.isNotEmpty) {
      final serverUrl = _accountRepo.getServerUrl();
      final uri = Uri.parse('$serverUrl/api/v1/auth/revoke');
      try {
        await http.post(uri, headers: _ngrokHeaders, body: {'refresh_token': refreshToken});
        _logger?.i('Auth: refresh token revoked');
      } catch (e) {
        _logger?.w('Auth: failed to revoke refresh token: $e');
      }
    }
    await clearTokens();
  }

  /// Clear all stored tokens without revoking.
  Future<void> clearTokens() async {
    _cachedAccessToken = null;
    _cachedAccessTokenExpiry = null;
    await _secureStorage.delete(key: _keyRefreshToken);
    await _secureStorage.delete(key: _keyAccessToken);
    await _secureStorage.delete(key: _keyAccessTokenExpiry);
    _logger?.i('Auth: tokens cleared');
  }

  Future<void> _storeTokens(Map<String, dynamic> json) async {
    final refreshToken = json['refresh_token'] as String;
    final accessToken = json['access_token'] as String;
    final expiresIn = json['expires_in'] as int;

    await _secureStorage.write(key: _keyRefreshToken, value: refreshToken);
    await _storeAccessToken(accessToken, expiresIn);
  }

  Future<void> _storeAccessToken(String token, int expiresIn) async {
    final expiry = DateTime.now().add(Duration(seconds: expiresIn));
    _cachedAccessToken = token;
    _cachedAccessTokenExpiry = expiry;
    await _secureStorage.write(key: _keyAccessToken, value: token);
    await _secureStorage.write(
      key: _keyAccessTokenExpiry,
      value: expiry.toIso8601String(),
    );
  }

  /// Generate a cryptographically random code verifier (43-128 characters).
  String _generateCodeVerifier() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  /// Generate a S256 code challenge from a code verifier.
  String _generateCodeChallenge(String verifier) {
    final bytes = utf8.encode(verifier);
    final digest = sha256.convert(bytes);
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }
}

/// PKCE parameters for the authorization URL.
class PkceParams {
  final String codeChallenge;
  final String codeChallengeMethod;

  PkceParams({required this.codeChallenge, required this.codeChallengeMethod});
}

/// Exception thrown when authentication fails.
class AuthenticationException implements Exception {
  final String message;
  AuthenticationException(this.message);

  @override
  String toString() => message;
}

@Riverpod(keepAlive: true)
Future<AuthService> authService(Ref ref) async {
  final secureStorage = ref.watch(secureStorageProvider);
  final accountRepo = await ref.watch(accountRepositoryProvider.future);
  final logger = ref.watch(loggerProvider);
  return AuthService(secureStorage, accountRepo, logger);
}
