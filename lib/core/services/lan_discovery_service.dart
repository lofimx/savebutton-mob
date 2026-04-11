import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kaya/core/services/logger_service.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'lan_discovery_service.g.dart';

/// Service to discover devices on the local network listening on a given port.
///
/// Uses the device's WiFi IP to determine the /24 subnet, then scans all 254
/// addresses with [Socket.connect] using short timeouts.
class LanDiscoveryService {
  final NetworkInfo _networkInfo = NetworkInfo();
  final LoggerService? _logger;
  bool _cancelled = false;

  LanDiscoveryService({LoggerService? logger}) : _logger = logger;

  /// Returns the device's WiFi IP address, or null if unavailable.
  Future<String?> getDeviceIp() async {
    try {
      final ip = await _networkInfo.getWifiIP();
      _logger?.d('LAN discovery: device WiFi IP is $ip');
      return ip;
    } catch (e) {
      _logger?.e('LAN discovery: failed to get WiFi IP', e);
      return null;
    }
  }

  /// Extracts the /24 subnet prefix from an IP address.
  /// e.g. "192.168.1.42" => "192.168.1"
  /// Returns null if the IP is not a valid IPv4 address.
  String? getSubnet(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return null;
    for (final part in parts) {
      final n = int.tryParse(part);
      if (n == null || n < 0 || n > 255) return null;
    }
    return '${parts[0]}.${parts[1]}.${parts[2]}';
  }

  /// Scans a /24 subnet for hosts listening on [port].
  ///
  /// Yields each discovered IP address as it is found.
  /// Scans addresses 1-254 in parallel batches to avoid file descriptor
  /// exhaustion.
  Stream<String> scanSubnet({
    required String subnet,
    required int port,
    Duration timeout = const Duration(milliseconds: 500),
  }) async* {
    _cancelled = false;
    _logger?.i('LAN discovery: scanning $subnet.0/24 on port $port');

    const batchSize = 50;
    for (var start = 1; start <= 254 && !_cancelled; start += batchSize) {
      final end = (start + batchSize - 1).clamp(1, 254);
      final futures = <Future<String?>>[];

      for (var i = start; i <= end; i++) {
        final host = '$subnet.$i';
        futures.add(_probeHost(host, port, timeout));
      }

      final results = await Future.wait(futures);
      for (final ip in results) {
        if (ip != null && !_cancelled) {
          _logger?.i('LAN discovery: found server at $ip:$port');
          yield ip;
        }
      }
    }

    _logger?.d('LAN discovery: scan complete');
  }

  /// Attempts to connect to [host]:[port] with a timeout.
  /// Returns the host if connection succeeds, null otherwise.
  Future<String?> _probeHost(String host, int port, Duration timeout) async {
    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      socket.destroy();
      return host;
    } catch (_) {
      return null;
    }
  }

  /// Cancels an in-progress scan.
  void cancel() {
    _cancelled = true;
    _logger?.d('LAN discovery: scan cancelled');
  }
}

/// Returns true if [url] points to localhost or a loopback address.
bool isLocalhostUrl(String url) {
  final lower = url.toLowerCase().trim();
  // Match localhost or 127.x.x.x in various URL formats
  return lower.contains('localhost') || lower.contains('127.0.0.1');
}

/// Returns true if [url] points to a private/LAN IP address
/// (10.x.x.x, 172.16-31.x.x, 192.168.x.x) but not localhost/loopback.
bool isPrivateIpUrl(String url) {
  final match = RegExp(r'(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})')
      .firstMatch(url);
  if (match == null) return false;
  final a = int.parse(match.group(1)!);
  final b = int.parse(match.group(2)!);
  if (a == 127) return false; // loopback, handled by isLocalhostUrl
  if (a == 10) return true;
  if (a == 172 && b >= 16 && b <= 31) return true;
  if (a == 192 && b == 168) return true;
  return false;
}

/// Extracts the port number from a URL string.
/// Returns 3000 as a sensible default for development servers.
int extractPort(String url) {
  try {
    // Handle URLs without a scheme
    final withScheme =
        url.contains('://') ? url : 'http://$url';
    final uri = Uri.parse(withScheme);
    if (uri.hasPort) return uri.port;
    // Default ports by scheme
    if (uri.scheme == 'https') return 443;
    return 80;
  } catch (_) {
    return 3000;
  }
}

@Riverpod(keepAlive: true)
LanDiscoveryService lanDiscoveryService(Ref ref) {
  final logger = ref.watch(loggerProvider);
  final service = LanDiscoveryService(logger: logger);
  ref.onDispose(() => service.cancel());
  return service;
}
