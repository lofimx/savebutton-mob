import 'package:freezed_annotation/freezed_annotation.dart';

part 'account_settings.freezed.dart';

/// User account settings for Kaya server sync.
@freezed
class AccountSettings with _$AccountSettings {
  static const defaultServerUrl = 'https://savebutton.com';
  const AccountSettings._();

  const factory AccountSettings({
    /// The Kaya server URL (default: https://savebutton.com)
    required String serverUrl,

    /// User's email for authentication
    String? email,

    /// Whether legacy password credentials are configured
    @Default(false) bool hasCredentials,

    /// Whether JWT token auth is configured (refresh token stored)
    @Default(false) bool hasTokenAuth,
  }) = _AccountSettings;

  factory AccountSettings.defaults() =>
      const AccountSettings(serverUrl: defaultServerUrl);

  /// Whether sync can be performed (either token or legacy credentials are set)
  bool get canSync =>
      (hasTokenAuth && email != null && email!.isNotEmpty) ||
      (hasCredentials && email != null && email!.isNotEmpty);

  /// Whether using the new JWT token-based auth
  bool get isTokenAuth => hasTokenAuth;
}
