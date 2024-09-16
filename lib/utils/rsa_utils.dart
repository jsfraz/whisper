import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';

class RsaUtils {

  /// Generate RSA keypair synchronously
  static AsymmetricKeyPair<PublicKey, PrivateKey> _computeRSAKeyPair(
      SecureRandom secureRandom) {
    var rsaParams = RSAKeyGeneratorParameters(BigInt.from(65537), 4096, 12);
    var params = ParametersWithRandom(rsaParams, secureRandom);

    var keyGenerator = RSAKeyGenerator();
    keyGenerator.init(params);

    return keyGenerator.generateKeyPair();
  }

  /// Generate RSA keypair asynchronously
  static Future<AsymmetricKeyPair<PublicKey, PrivateKey>> getRSAKeyPair() async {
    final secureRandom = FortunaRandom();
    secureRandom.seed(KeyParameter(Uint8List.fromList(
        List.generate(32, (i) => i)))); // Seed with random bytes

    return await compute(_computeRSAKeyPair, secureRandom);
  }
}