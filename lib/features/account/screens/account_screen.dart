import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:go_router/go_router.dart';
import 'package:kaya/core/services/logger_service.dart';
import 'package:kaya/core/widgets/kaya_icon.dart';
import 'package:kaya/features/account/screens/troubleshooting_screen.dart';
import 'package:kaya/features/account/models/account_settings.dart';
import 'package:kaya/features/account/services/account_repository.dart';
import 'package:kaya/features/account/services/auth_service.dart';
import 'package:kaya/features/sync/services/sync_service.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Screen for managing account settings.
class AccountScreen extends ConsumerStatefulWidget {
  static const routePath = '/account';
  static const routeName = 'account';

  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  final _serverController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _passwordVisible = false;
  bool _testing = false;
  bool _syncing = false;
  bool _authenticating = false;
  bool _loggingOut = false;
  bool _loaded = false;

  @override
  void dispose() {
    _serverController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    if (_loaded) return;

    final repo = await ref.read(accountRepositoryProvider.future);
    final settings = await repo.loadSettings();

    _serverController.text = settings.serverUrl;
    _emailController.text = settings.email ?? '';

    // Only load password for legacy auth
    if (!settings.hasTokenAuth) {
      final password = await repo.getPassword();
      _passwordController.text = password ?? '';
    }

    _loaded = true;
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(accountSettingsNotifierProvider);
    final syncStatus = ref.watch(syncControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: settingsAsync.when(
        data: (settings) {
          _loadSettings();
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildServerSection(),
                const SizedBox(height: 24),
                if (settings.hasTokenAuth)
                  _buildConnectedSection(settings)
                else
                  _buildLoginSection(settings),
                const SizedBox(height: 24),
                if (settings.canSync) ...[
                  _buildActionsSection(syncStatus),
                  const SizedBox(height: 24),
                ],
                _buildTroubleshootingSection(),
              ],
            ),
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(semanticsLabel: 'Loading settings'),
        ),
        error: (error, _) => Center(child: Text('Error: $error')),
      ),
    );
  }

  Widget _buildServerSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Server', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            TextField(
              controller: _serverController,
              decoration: const InputDecoration(
                labelText: 'Save Button Server',
                hintText: AccountSettings.defaultServerUrl,
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
              onChanged: (_) => _saveServerUrl(),
            ),
          ],
        ),
      ),
    );
  }

  /// Shown when the user is authenticated with JWT tokens.
  Widget _buildConnectedSection(AccountSettings settings) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Connected', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(KayaIcon.checkCircle, color: Colors.green, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Signed in as ${settings.email ?? "unknown"}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _loggingOut ? null : _logout,
              icon: _loggingOut
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        semanticsLabel: 'Signing out',
                      ),
                    )
                  : Icon(KayaIcon.logout),
              label: const Text('Sign Out'),
            ),
          ],
        ),
      ),
    );
  }

  /// Shown when the user is not authenticated with tokens.
  /// Provides both email/password login and OAuth options.
  Widget _buildLoginSection(AccountSettings settings) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Sign In',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),

            // Email/password form
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
              onChanged: (_) => _saveEmail(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              decoration: InputDecoration(
                labelText: 'Password',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _passwordVisible
                        ? KayaIcon.visibilityOff
                        : KayaIcon.visibility,
                  ),
                  onPressed: () {
                    setState(() {
                      _passwordVisible = !_passwordVisible;
                    });
                  },
                  tooltip:
                      _passwordVisible ? 'Hide password' : 'Show password',
                ),
              ),
              obscureText: !_passwordVisible,
              autocorrect: false,
              enableSuggestions: false,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _authenticating ? null : _signInWithPassword,
              child: _authenticating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        semanticsLabel: 'Signing in',
                      ),
                    )
                  : const Text('Sign In'),
            ),

            // Divider
            const SizedBox(height: 20),
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'or',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ),
                const Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 20),

            // OAuth buttons
            OutlinedButton.icon(
              onPressed: _authenticating ? null : _signInWithOAuth,
              icon: Icon(KayaIcon.language),
              label: const Text('Sign In with Browser'),
            ),
            const SizedBox(height: 8),
            Text(
              'Opens your browser to sign in with Google, Microsoft, or email',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
              textAlign: TextAlign.center,
            ),

            // Legacy mode hint
            if (settings.hasCredentials && !settings.hasTokenAuth) ...[
              const SizedBox(height: 16),
              Text(
                'Currently using legacy sync. Sign in above to upgrade to token-based auth.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.tertiary,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActionsSection(SyncStatus syncStatus) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Actions', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _testing ? null : _testConnection,
              icon: _testing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        semanticsLabel: 'Testing connection',
                      ),
                    )
                  : Icon(KayaIcon.testConnection),
              label: const Text('Test Connection'),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _syncing || syncStatus == SyncStatus.syncing
                  ? null
                  : _forceSync,
              icon: _syncing || syncStatus == SyncStatus.syncing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        semanticsLabel: 'Syncing',
                      ),
                    )
                  : Icon(KayaIcon.sync),
              label: const Text('Force Sync'),
            ),
            if (syncStatus == SyncStatus.error) ...[
              const SizedBox(height: 8),
              Text(
                'Last sync had errors - check Troubleshooting',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTroubleshootingSection() {
    return Card(
      child: ListTile(
        leading: Icon(KayaIcon.bugReport),
        title: const Text('Troubleshooting'),
        subtitle: const Text('View logs and report issues'),
        trailing: Icon(KayaIcon.chevronRight),
        onTap: () => context.push(TroubleshootingScreen.routePath),
      ),
    );
  }

  Future<void> _saveServerUrl() async {
    final notifier = ref.read(accountSettingsNotifierProvider.notifier);
    await notifier.updateServerUrl(_serverController.text.trim());
  }

  Future<void> _saveEmail() async {
    final notifier = ref.read(accountSettingsNotifierProvider.notifier);
    await notifier.updateEmail(_emailController.text.trim());
  }

  /// Sign in with email/password using the password grant.
  Future<void> _signInWithPassword() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      _showSnackBar('Please enter email and password', isError: true);
      return;
    }

    setState(() => _authenticating = true);

    try {
      final authService = await ref.read(authServiceProvider.future);
      final deviceInfo = await _getDeviceInfo();

      final userEmail = await authService.authenticateWithPassword(
        email: email,
        password: password,
        deviceName: deviceInfo.name,
        deviceType: deviceInfo.type,
        appVersion: deviceInfo.version,
      );

      // Save the email and refresh settings
      final notifier = ref.read(accountSettingsNotifierProvider.notifier);
      await notifier.updateEmail(userEmail);
      await notifier.refresh();

      // Clear the password field (no longer stored)
      _passwordController.clear();

      if (mounted) {
        _showSnackBar('Signed in as $userEmail');
      }
    } on AuthenticationException catch (e) {
      if (mounted) {
        _showSnackBar(e.message, isError: true);
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Sign in failed: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _authenticating = false);
      }
    }
  }

  /// Sign in via OAuth using the browser-based PKCE flow.
  /// Opens a Chrome Custom Tab (Android) or ASWebAuthenticationSession (iOS)
  /// to the server's login page, then handles the savebutton:// callback.
  Future<void> _signInWithOAuth() async {
    setState(() => _authenticating = true);

    try {
      final authService = await ref.read(authServiceProvider.future);
      final deviceInfo = await _getDeviceInfo();

      // Build the authorize URL with PKCE params
      final authorizeUrl = authService.buildAuthorizeUrl(
        deviceName: deviceInfo.name,
        deviceType: deviceInfo.type,
        state: DateTime.now().millisecondsSinceEpoch.toString(),
      );

      // Open browser and wait for callback
      final callbackUrl = await FlutterWebAuth2.authenticate(
        url: authorizeUrl.toString(),
        callbackUrlScheme: 'savebutton',
      );

      // Extract the authorization code from the callback URL
      final callbackUri = Uri.parse(callbackUrl);
      final code = callbackUri.queryParameters['code'];

      if (code == null || code.isEmpty) {
        throw AuthenticationException('No authorization code received');
      }

      // Exchange the code for tokens
      final userEmail = await authService.exchangeAuthorizationCode(
        code: code,
        deviceName: deviceInfo.name,
        deviceType: deviceInfo.type,
        appVersion: deviceInfo.version,
      );

      final notifier = ref.read(accountSettingsNotifierProvider.notifier);
      await notifier.updateEmail(userEmail);
      await notifier.refresh();

      if (mounted) {
        _showSnackBar('Signed in as $userEmail');
      }
    } catch (e) {
      final logger = ref.read(loggerProvider);
      logger?.e('OAuth sign in failed', e);
      if (mounted) {
        _showSnackBar('Sign in failed: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _authenticating = false);
      }
    }
  }

  /// Sign out: revoke token and clear credentials.
  Future<void> _logout() async {
    setState(() => _loggingOut = true);

    try {
      final authService = await ref.read(authServiceProvider.future);
      await authService.logout();

      final notifier = ref.read(accountSettingsNotifierProvider.notifier);
      await notifier.clearCredentials();
      await notifier.refresh();

      _loaded = false;
      _emailController.clear();
      _passwordController.clear();

      if (mounted) {
        _showSnackBar('Signed out');
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Sign out failed: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _loggingOut = false);
      }
    }
  }

  Future<void> _testConnection() async {
    setState(() => _testing = true);

    try {
      final controller = ref.read(syncControllerProvider.notifier);
      final success = await controller.testConnection();

      if (mounted) {
        _showSnackBar(
          success ? 'Connection successful!' : 'Connection failed',
          isError: !success,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _testing = false);
      }
    }
  }

  Future<void> _forceSync() async {
    setState(() => _syncing = true);

    try {
      final controller = ref.read(syncControllerProvider.notifier);
      final result = await controller.forceSync();

      if (mounted) {
        final message = result.hasErrors
            ? 'Sync completed with errors'
            : result.hasChanges
                ? 'Sync complete: ${result.angaDownloaded + result.metaDownloaded + result.faviconDownloaded + result.wordsDownloaded} downloaded, '
                    '${result.angaUploaded + result.metaUploaded} uploaded'
                : 'Already in sync';

        _showSnackBar(message, isError: result.hasErrors);
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Sync error: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _syncing = false);
      }
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : null,
      ),
    );
  }

  Future<_DeviceInfo> _getDeviceInfo() async {
    final deviceInfoPlugin = DeviceInfoPlugin();
    String name;
    String type;

    if (Platform.isAndroid) {
      final info = await deviceInfoPlugin.androidInfo;
      name = '${info.brand} ${info.model}';
      type = 'mobile_android';
    } else if (Platform.isIOS) {
      final info = await deviceInfoPlugin.iosInfo;
      name = info.name;
      type = 'mobile_ios';
    } else {
      name = 'Unknown Device';
      type = 'mobile_android';
    }

    String? version;
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      version = packageInfo.version;
    } catch (_) {
      // package_info_plus may not be available
    }

    return _DeviceInfo(name: name, type: type, version: version);
  }
}

class _DeviceInfo {
  final String name;
  final String type;
  final String? version;

  _DeviceInfo({required this.name, required this.type, this.version});
}
