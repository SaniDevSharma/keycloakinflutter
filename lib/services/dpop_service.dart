import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart' as djwt;
import 'package:pointycastle/export.dart' as pc;
import 'package:uuid/uuid.dart';

import 'secure_storage_service.dart';

/// Service responsible for DPoP (Demonstrating Proof-of-Possession) proof
/// generation as specified in RFC 9449.
///
/// Uses an EC P-256 key pair: private key is persisted in secure storage;
/// the public key is embedded in every DPoP proof JWT header as a JWK.
class DpopService {
  DpopService._();

  static final DpopService instance = DpopService._();

  static const String _privateKeyStorageKey = 'dpop_private_key_b64';
  static const String _publicKeyStorageKey = 'dpop_public_key_jwk';

  pc.ECPrivateKey? _privateKey;
  Map<String, dynamic>? _publicJwk;

  // ──────────────────────────────────────────
  // Public API
  // ──────────────────────────────────────────

  /// Initialises the DPoP service. Loads an existing key pair from secure
  /// storage, or generates a new one if none is found.
  Future<void> init() async {
    final storedPrivateB64 =
        await SecureStorageService.instance.read(_privateKeyStorageKey);
    final storedPublicJwk =
        await SecureStorageService.instance.read(_publicKeyStorageKey);

    if (storedPrivateB64 != null && storedPublicJwk != null) {
      _privateKey = _privateKeyFromBase64(storedPrivateB64);
      _publicJwk = jsonDecode(storedPublicJwk) as Map<String, dynamic>;
    } else {
      await _generateAndStoreKeyPair();
    }
  }

  /// Builds a DPoP proof JWT for the given HTTP [method] and [url].
  ///
  /// If [accessToken] is provided, the `ath` claim (SHA-256 of the token)
  /// is included — required when using DPoP-bound access tokens for
  /// resource server requests.
  ///
  /// If [nonce] is provided (from a Keycloak `use_dpop_nonce` response),
  /// it is included as the `nonce` claim in the proof payload.
  String buildDpopProof(String method, String url,
      {String? accessToken, String? nonce}) {
    if (_privateKey == null || _publicJwk == null) {
      throw StateError('DpopService not initialised. Call init() first.');
    }

    final payload = <String, dynamic>{
      'jti': const Uuid().v4(),
      'htm': method.toUpperCase(),
      'htu': _stripQuery(url),
      'iat': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    };

    if (accessToken != null) {
      // ath = BASE64URL(SHA-256(ASCII(access_token)))
      final digest = sha256.convert(utf8.encode(accessToken));
      payload['ath'] = base64Url.encode(digest.bytes).replaceAll('=', '');
    }

    if (nonce != null) {
      payload['nonce'] = nonce;
    }

    // Build the JWT with a custom header that includes the public JWK.
    // dart_jsonwebtoken's ECPrivateKey is used here for signing.
    final jwt = djwt.JWT(payload, header: {
      'typ': 'dpop+jwt',
      'alg': 'ES256',
      'jwk': _publicJwk,
    });

    // Convert pointycastle private key bytes to dart_jsonwebtoken ECPrivateKey.
    final dBytes = _bigIntToBytes(_privateKey!.d!, 32);
    final jwtPrivKey = djwt.ECPrivateKey(
      _bytesToPkcs8Pem(dBytes),
    );

    return jwt.sign(jwtPrivKey, algorithm: djwt.JWTAlgorithm.ES256);
  }

  // ──────────────────────────────────────────
  // Private helpers
  // ──────────────────────────────────────────

  Future<void> _generateAndStoreKeyPair() async {
    final keyPair = _generateEcKeyPair();
    _privateKey = keyPair.privateKey as pc.ECPrivateKey;
    final publicKey = keyPair.publicKey as pc.ECPublicKey;

    _publicJwk = _ecPublicKeyToJwk(publicKey);

    // Persist to secure storage (store only the raw `d` scalar).
    final dBytes = _bigIntToBytes(_privateKey!.d!, 32);
    await SecureStorageService.instance
        .write(_privateKeyStorageKey, base64.encode(dBytes));
    await SecureStorageService.instance
        .write(_publicKeyStorageKey, jsonEncode(_publicJwk));
  }

  /// Generates an EC P-256 key pair using PointyCastle.
  pc.AsymmetricKeyPair<pc.PublicKey, pc.PrivateKey> _generateEcKeyPair() {
    final domainParams = pc.ECDomainParameters('prime256v1');
    final secureRandom = _buildSecureRandom();

    final keyGenerator = pc.KeyGenerator('EC');
    keyGenerator.init(pc.ParametersWithRandom(
      pc.ECKeyGeneratorParameters(domainParams),
      secureRandom,
    ));

    return keyGenerator.generateKeyPair();
  }

  /// Converts a PointyCastle [ECPublicKey] into a JWK map (kty=EC, crv=P-256).
  Map<String, dynamic> _ecPublicKeyToJwk(pc.ECPublicKey key) {
    final q = key.Q!;
    final x = q.x!.toBigInteger()!;
    final y = q.y!.toBigInteger()!;

    String bigIntToBase64Url(BigInt v) {
      final bytes = _bigIntToBytes(v, 32);
      return base64Url.encode(bytes).replaceAll('=', '');
    }

    return {
      'kty': 'EC',
      'crv': 'P-256',
      'x': bigIntToBase64Url(x),
      'y': bigIntToBase64Url(y),
    };
  }

  /// Reconstructs a [pc.ECPrivateKey] from a base64-encoded raw `d` value.
  pc.ECPrivateKey _privateKeyFromBase64(String b64) {
    final dBytes = base64.decode(b64);
    final d = _bytesToBigInt(dBytes);
    return pc.ECPrivateKey(d, pc.ECDomainParameters('prime256v1'));
  }

  /// Builds a minimal PKCS#8 PEM from a raw 32-byte EC P-256 private key `d`.
  ///
  /// dart_jsonwebtoken's [ECPrivateKey] expects PEM format.
  String _bytesToPkcs8Pem(Uint8List dBytes) {
    // SEC1 ECPrivateKey DER for P-256:
    // SEQUENCE {
    //   INTEGER 1 (version)
    //   OCTET STRING (private key d)
    //   [0] OID 1.2.840.10045.3.1.7 (prime256v1)
    // }
    final oidP256 = [0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07];
    final privateKeyOctetString = [0x04, 0x20, ...dBytes];
    final contextTag0 = [0xa0, oidP256.length, ...oidP256];
    final sequence = [
      0x02, 0x01, 0x01, // INTEGER 1
      ...privateKeyOctetString,
      ...contextTag0,
    ];
    final outerLen = sequence.length;
    final der = Uint8List.fromList([
      0x30,
      if (outerLen > 127) ...[0x81, outerLen],
      if (outerLen <= 127) outerLen,
      ...sequence,
    ]);

    final b64 = base64.encode(der);
    // Wrap in PEM headers.
    final lines = StringBuffer();
    lines.writeln('-----BEGIN EC PRIVATE KEY-----');
    for (var i = 0; i < b64.length; i += 64) {
      lines.writeln(b64.substring(i, i + 64 > b64.length ? b64.length : i + 64));
    }
    lines.write('-----END EC PRIVATE KEY-----');
    return lines.toString();
  }

  /// Removes query string / fragment from a URL so `htu` only contains
  /// the scheme + host + path, as required by RFC 9449 §4.2.
  ///
  /// IMPORTANT: Do NOT use `uri.replace(query:'', fragment:'').toString()` —
  /// Dart's Uri sets hasFragment=true for empty-string fragment, causing
  /// toString() to emit a trailing '#' which breaks DPoP validation.
  String _stripQuery(String url) {
    final uri = Uri.parse(url);
    // Reconstruct from scratch with only the parts DPoP needs.
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.port,
      path: uri.path,
    ).toString();
  }

  // ── Byte / BigInt utilities ──────────────

  Uint8List _bigIntToBytes(BigInt value, int length) {
    final hex = value.toRadixString(16).padLeft(length * 2, '0');
    final result = Uint8List(length);
    for (var i = 0; i < length; i++) {
      result[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return result;
  }

  BigInt _bytesToBigInt(Uint8List bytes) {
    BigInt result = BigInt.zero;
    for (final b in bytes) {
      result = (result << 8) | BigInt.from(b);
    }
    return result;
  }

  pc.SecureRandom _buildSecureRandom() {
    final random = Random.secure();
    final seed = Uint8List(32);
    for (var i = 0; i < seed.length; i++) {
      seed[i] = random.nextInt(256);
    }
    return pc.SecureRandom('Fortuna')..seed(pc.KeyParameter(seed));
  }
}
