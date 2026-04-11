import 'package:flutter_test/flutter_test.dart';
import 'package:kaya/core/services/lan_discovery_service.dart';

void main() {
  group('LanDiscoveryService', () {
    late LanDiscoveryService service;

    setUp(() {
      service = LanDiscoveryService();
    });

    group('getSubnet', () {
      test('extracts /24 prefix from valid IPv4', () {
        expect(service.getSubnet('192.168.1.42'), equals('192.168.1'));
      });

      test('works with different subnets', () {
        expect(service.getSubnet('10.0.0.1'), equals('10.0.0'));
        expect(service.getSubnet('172.16.254.100'), equals('172.16.254'));
      });

      test('returns null for too few octets', () {
        expect(service.getSubnet('192.168.1'), isNull);
      });

      test('returns null for too many octets', () {
        expect(service.getSubnet('192.168.1.1.1'), isNull);
      });

      test('returns null for non-numeric octets', () {
        expect(service.getSubnet('192.168.abc.1'), isNull);
      });

      test('returns null for out-of-range octets', () {
        expect(service.getSubnet('192.168.1.256'), isNull);
        expect(service.getSubnet('192.168.-1.1'), isNull);
      });

      test('returns null for empty string', () {
        expect(service.getSubnet(''), isNull);
      });
    });
  });

  group('isLocalhostUrl', () {
    test('detects localhost', () {
      expect(isLocalhostUrl('http://localhost:3000'), isTrue);
    });

    test('detects LOCALHOST (case insensitive)', () {
      expect(isLocalhostUrl('http://LOCALHOST:3000'), isTrue);
    });

    test('detects 127.0.0.1', () {
      expect(isLocalhostUrl('http://127.0.0.1:3000'), isTrue);
    });

    test('detects localhost without scheme', () {
      expect(isLocalhostUrl('localhost:3000'), isTrue);
    });

    test('detects localhost with path', () {
      expect(isLocalhostUrl('http://localhost:3000/api'), isTrue);
    });

    test('returns false for normal URLs', () {
      expect(isLocalhostUrl('https://savebutton.com'), isFalse);
    });

    test('returns false for IP addresses that are not loopback', () {
      expect(isLocalhostUrl('http://192.168.1.100:3000'), isFalse);
    });

    test('returns false for empty string', () {
      expect(isLocalhostUrl(''), isFalse);
    });
  });

  group('extractPort', () {
    test('extracts explicit port', () {
      expect(extractPort('http://localhost:3000'), equals(3000));
    });

    test('extracts port from URL with path', () {
      expect(extractPort('http://localhost:8080/api/v1'), equals(8080));
    });

    test('returns 80 for http without port', () {
      expect(extractPort('http://example.com'), equals(80));
    });

    test('returns 443 for https without port', () {
      expect(extractPort('https://example.com'), equals(443));
    });

    test('handles URL without scheme', () {
      expect(extractPort('localhost:3000'), equals(3000));
    });

    test('extracts port from 127.0.0.1', () {
      expect(extractPort('http://127.0.0.1:4000'), equals(4000));
    });
  });

  group('isPrivateIpUrl', () {
    test('detects 192.168.x.x', () {
      expect(isPrivateIpUrl('http://192.168.1.100:3000'), isTrue);
      expect(isPrivateIpUrl('http://192.168.68.103:3000'), isTrue);
    });

    test('detects 10.x.x.x', () {
      expect(isPrivateIpUrl('http://10.0.0.1:3000'), isTrue);
      expect(isPrivateIpUrl('http://10.255.255.255'), isTrue);
    });

    test('detects 172.16-31.x.x', () {
      expect(isPrivateIpUrl('http://172.16.0.1:3000'), isTrue);
      expect(isPrivateIpUrl('http://172.31.255.255'), isTrue);
    });

    test('returns false for 172.15.x.x and 172.32.x.x', () {
      expect(isPrivateIpUrl('http://172.15.0.1:3000'), isFalse);
      expect(isPrivateIpUrl('http://172.32.0.1:3000'), isFalse);
    });

    test('returns false for loopback (handled by isLocalhostUrl)', () {
      expect(isPrivateIpUrl('http://127.0.0.1:3000'), isFalse);
    });

    test('returns false for public IPs', () {
      expect(isPrivateIpUrl('http://8.8.8.8'), isFalse);
      expect(isPrivateIpUrl('http://203.0.113.1:3000'), isFalse);
    });

    test('returns false for hostnames', () {
      expect(isPrivateIpUrl('https://savebutton.com'), isFalse);
      expect(isPrivateIpUrl('http://localhost:3000'), isFalse);
    });

    test('returns false for empty string', () {
      expect(isPrivateIpUrl(''), isFalse);
    });
  });
}
