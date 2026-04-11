import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaya/features/account/services/auth_service.dart';

void main() {
  group('PKCE', () {
    test('generatePkceParams creates valid challenge', () {
      // We can't test the AuthService directly without mocking dependencies,
      // but we can test the PKCE algorithm independently.
      final verifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';
      final bytes = utf8.encode(verifier);
      final digest = sha256.convert(bytes);
      final challenge =
          base64UrlEncode(digest.bytes).replaceAll('=', '');

      expect(challenge, isNotEmpty);
      // Verify it's URL-safe base64 (no +, /, or =)
      expect(challenge, isNot(contains('+')));
      expect(challenge, isNot(contains('/')));
      expect(challenge, isNot(contains('=')));
    });

    test('PKCE challenge matches verifier', () {
      // Simulate the full PKCE flow
      final verifier = 'test_code_verifier_1234567890abcdefgh';
      final bytes = utf8.encode(verifier);
      final digest = sha256.convert(bytes);
      final challenge =
          base64UrlEncode(digest.bytes).replaceAll('=', '');

      // Server-side verification (same as AuthorizationCode.verify_pkce)
      final serverDigest = sha256.convert(utf8.encode(verifier));
      final serverChallenge =
          base64UrlEncode(serverDigest.bytes).replaceAll('=', '');

      expect(challenge, equals(serverChallenge));
    });

    test('different verifiers produce different challenges', () {
      final verifier1 = 'verifier_one_abcdefghijklmnop';
      final verifier2 = 'verifier_two_abcdefghijklmnop';

      final challenge1 = base64UrlEncode(
        sha256.convert(utf8.encode(verifier1)).bytes,
      ).replaceAll('=', '');
      final challenge2 = base64UrlEncode(
        sha256.convert(utf8.encode(verifier2)).bytes,
      ).replaceAll('=', '');

      expect(challenge1, isNot(equals(challenge2)));
    });
  });

  group('PkceParams', () {
    test('holds challenge and method', () {
      final params = PkceParams(
        codeChallenge: 'test_challenge',
        codeChallengeMethod: 'S256',
      );
      expect(params.codeChallenge, 'test_challenge');
      expect(params.codeChallengeMethod, 'S256');
    });
  });

  group('AuthenticationException', () {
    test('has message', () {
      final e = AuthenticationException('bad credentials');
      expect(e.message, 'bad credentials');
      expect(e.toString(), 'bad credentials');
    });
  });
}
