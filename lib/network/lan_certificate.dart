import 'dart:convert';
import 'dart:io';

import 'package:basic_utils/basic_utils.dart';

class LanCertificate {
  const LanCertificate({required this.context, required this.fingerprint});

  final SecurityContext context;
  final String fingerprint;

  static LanCertificate create(String host) {
    final pair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
    final privateKey = pair.privateKey as RSAPrivateKey;
    final publicKey = pair.publicKey as RSAPublicKey;
    final csr = X509Utils.generateRsaCsrPem(
      {'CN': host, 'O': 'FAP Attendance Lab'},
      privateKey,
      publicKey,
      san: [host],
    );
    final certificate = X509Utils.generateSelfSignedCertificate(
      privateKey,
      csr,
      1,
      sans: [host],
    );
    final privatePem = CryptoUtils.encodeRSAPrivateKeyToPemPkcs1(privateKey);
    final context = SecurityContext()
      ..useCertificateChainBytes(utf8.encode(certificate))
      ..usePrivateKeyBytes(utf8.encode(privatePem));
    final fingerprint = X509Utils.x509CertificateFromPem(certificate)
        .sha1Thumbprint!;
    return LanCertificate(context: context, fingerprint: fingerprint);
  }
}
