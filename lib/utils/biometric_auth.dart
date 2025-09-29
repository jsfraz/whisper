import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fluttertoast/fluttertoast.dart';

import 'cache_utils.dart';

class BiometricAuth {
  static final LocalAuthentication _auth = LocalAuthentication();
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static const String _biometricKeyStorageKey = 'whisper_secure_key';

  /// Checks if biometric authentication is available on the device
  static Future<bool> isBiometricAvailable() async {
    bool canAuthenticateWithBiometrics;
    bool canAuthenticate;

    try {
      canAuthenticateWithBiometrics = await _auth.canCheckBiometrics;
      canAuthenticate = canAuthenticateWithBiometrics || await _auth.isDeviceSupported();
    } on PlatformException catch (e) {
      debugPrint(e.toString());
      return false;
    }

    if (!canAuthenticate) {
      return false;
    }

    // Check available biometric types
    try {
      final availableBiometrics = await _auth.getAvailableBiometrics();
      return availableBiometrics.isNotEmpty;
    } on PlatformException catch (e) {
      debugPrint(e.toString());
      return false;
    }
  }

  /// Saves the decryption key to a secure storage protected by biometrics
  static Future<bool> storeEncryptionKey(List<int> key, BuildContext context) async {
    try {
      // Convert the key to a string for storage
      final String keyString = key.join(',');

      // Verify biometric credentials before storing the key
      bool authenticated = await authenticate(
        'biometricSetupReason'.tr(), 
        'biometricSetupAuth'.tr(),
        context);
      
      if (authenticated) {
        // Store the key securely
        await _secureStorage.write(key: _biometricKeyStorageKey, value: keyString);
        // Enable biometric authentication
        await CacheUtils.setBiometryEnabled(true);
        return true;
      }
      
      return false;
    } catch (e) {
      debugPrint('Error storing encryption key: $e');
      await Fluttertoast.showToast(
        msg: 'biometricSetupFailed'.tr(), 
        backgroundColor: Colors.red
      );
      return false;
    }
  }

  /// Delete the decryption key from secure storage and disable biometric authentication
  static Future<bool> disableBiometricAuth(BuildContext context) async {
    try {
      // Verify biometric credentials before storing the key
      bool authenticated = await authenticate(
        'biometricSetupReason'.tr(), 
        'biometricSetupAuth'.tr(),
        context);
      
      if (authenticated) {
        // Delete the stored key
        await _secureStorage.delete(key: _biometricKeyStorageKey);
        // Disable biometric authentication
        await CacheUtils.setBiometryEnabled(false);
        return true;
      }
      
      return false;
    } catch (e) {
      debugPrint('Error disabling encryption key: $e');
      await Fluttertoast.showToast(
        msg: 'biometricSetupFailed'.tr(), 
        backgroundColor: Colors.red
      );
      return false;
    }
  }

  /// Gets the decryption key from secure storage after biometric authentication
  static Future<List<int>?> getEncryptionKey(BuildContext context) async {
    try {
      // Verify biometric credentials before retrieving the key
      bool authenticated = await authenticate(
        'biometricAuthReason'.tr(), 
        'biometricAuthPrompt'.tr(),
        context);
      
      if (authenticated) {
        // Get the stored key
        final String? keyString = await _secureStorage.read(key: _biometricKeyStorageKey);
        if (keyString != null && keyString.isNotEmpty) {
          // Convert the string back to a list of bytes
          return keyString.split(',').map((s) => int.parse(s)).toList();
        }
      }
      
      return null;
    } catch (e) {
      debugPrint('Error retrieving encryption key: $e');
      return null;
    }
  }

  /// Clears the decryption key from secure storage
  static Future<void> clearEncryptionKey() async {
    await _secureStorage.delete(key: _biometricKeyStorageKey);
  }

  /// Performs biometric authentication
  static Future<bool> authenticate(String reason, String authString, BuildContext context) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        )
      );
    } on PlatformException catch (e) {
      debugPrint('Authentication error: $e');
      await Fluttertoast.showToast(
        msg: 'biometricAuthFailed'.tr(), 
        backgroundColor: Colors.red
      );
      return false;
    }
  }
}