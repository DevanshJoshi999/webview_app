import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:local_auth_darwin/local_auth_darwin.dart';

final storage = FlutterSecureStorage(
  aOptions: AndroidOptions(
    encryptedSharedPreferences: true,
  ),
);
final auth = LocalAuthentication();

String? decryptAdValue(String encryptedText, String keyString) {
  try {
    final key = encrypt.Key.fromUtf8(keyString.substring(0, 32));
    final iv = encrypt.IV.fromUtf8(keyString.substring(0, 16));
    final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));
    final decrypted = encrypter.decrypt64(encryptedText, iv: iv);
    return decrypted;
  } catch (e) {
    debugPrint("❌ Decryption failed: $e");
    return null;
  }
}

Future<bool> authenticateUser() async {
  try {
    final didAuthenticate = await auth.authenticate(
      authMessages: [
        const AndroidAuthMessages(
          signInTitle: 'Unlock Nagarik Sharafi',
          biometricNotRecognized: 'Fingerprint not recognized. Try again.',
          biometricSuccess: 'Authentication successful!',
          cancelButton: 'Cancel',
        ),
        const IOSAuthMessages(
          lockOut: 'Biometric authentication is locked. Try later.',
          cancelButton: 'Cancel',
          goToSettingsButton: 'Settings',
          goToSettingsDescription:
          'Please enable Touch ID or Face ID in Settings.',
        ),
      ],
      localizedReason: 'Use your fingerprint to continue',
      options: const AuthenticationOptions(
        biometricOnly: true,
        stickyAuth: false,
      ),
    );
    return didAuthenticate;
  } catch (e) {
    if (e.toString().contains("User canceled") ||
        e.toString().contains("User cancellation")) {
      debugPrint("🟡 User canceled biometric prompt.");
      return false;
    }

    debugPrint("❌ Biometric error: $e");
    return false;
  }
}

Future<void> saveCredentials(String username, String password) async {
  await storage.write(key: "username", value: username);
  await storage.write(key: "password", value: password);
}

Future<Map<String, String?>> getCredentials() async {
  final username = await storage.read(key: "username");
  final password = await storage.read(key: "password");
  return {"username": username, "password": password};
}

Future<void> initializeSecureStorage() async {
  try {
    await storage.containsKey(key: 'biometric_enabled');
  } catch (e) {
    debugPrint('⚠️ SecureStorage data invalid or corrupted. Resetting...');
    await storage.deleteAll();
  }
}
