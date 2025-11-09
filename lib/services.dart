import 'dart:convert';
import 'package:banking_app_webview/utils.dart';
import 'package:encrypt/encrypt.dart';
import 'package:flutter/material.dart' hide Key;
import 'package:flutter/services.dart';
import 'package:flutter_svg/svg.dart';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:fluttertoast/fluttertoast.dart';

class BiometricSession {
  static bool biometricPassed = false;
}

class BiometricGate extends StatefulWidget {
  final Widget child;

  const BiometricGate({super.key, required this.child});

  @override
  State<BiometricGate> createState() => _BiometricGateState();
}

class _BiometricGateState extends State<BiometricGate> {
  bool? _authenticated;
  Map<String, dynamic>? userData;
  DateTime? _lastBackPress;
  bool _isLoadingUserData = true;
  bool _biometricPromptShown = false;


  @override
  void initState() {
    super.initState();
    _initUserData();
    _checkBiometric();
  }

  Future<void> _initUserData() async {
    try {
      final encryptedAd = await storage.read(key: "ad");

      if (encryptedAd != null && encryptedAd.isNotEmpty) {
        print("📦 Encrypted AD (Base64): $encryptedAd");

        const passphrase =
            'QBI2llvXLuKL3D4I7PaApKZSdYNxnVRAURxuNznVxjmtsrGpAwUiSaMZ2UFXkYYb4KT5Vu9vwiGYN3afj8mJ0I3zicZiOqUAeVdN';

        final decrypted = _decryptOpenSSLAES(encryptedAd, passphrase);
        debugPrint("✅ Properly decrypted JSON: $decrypted", wrapWidth: 1024);

        final parsed = jsonDecode(decrypted);
        await _saveUserData(parsed);
        if (mounted) {
          setState(() {
          userData = parsed;
          _isLoadingUserData = false;
        });
        }
      } else {
        if (mounted) setState(() => _isLoadingUserData = false);
      }
    } catch (e) {
      print("❌ Failed to init user data: $e");
      if (mounted) setState(() => _isLoadingUserData = false);
    }
  }

  Future<void> _saveUserData(Map<String, dynamic> parsed) async {
    await storage.write(key: "uName", value: parsed["uName"]);
    await storage.write(key: "uImage", value: parsed["uImage"]);
    await storage.write(key: "cName", value: parsed["cName"]);
    await storage.write(key: "cLogo", value: parsed["cLogo"]);
    await storage.write(key: "cShortName", value: parsed["cShortName"]);
    await storage.write(key: "cContactNo", value: parsed["cContactNo"]);
  }

  String _decryptOpenSSLAES(String base64Cipher, String passphrase) {
    final cipherData = base64Decode(base64Cipher);

    final saltHeader = utf8.decode(cipherData.sublist(0, 8));
    if (saltHeader != 'Salted__') {
      throw ArgumentError('Not a valid OpenSSL-salted format');
    }

    final salt = cipherData.sublist(8, 16);
    final encrypted = cipherData.sublist(16);

    final derived = _evpBytesToKey(
      passphrase: passphrase,
      salt: salt,
      keyLen: 32,
      ivLen: 16,
    );

    final key = Key(derived.item1);
    final iv = IV(derived.item2);

    final encrypter = Encrypter(AES(key, mode: AESMode.cbc, padding: 'PKCS7'));
    return encrypter.decrypt(Encrypted(encrypted), iv: iv);
  }

  Tuple2<Uint8List, Uint8List> _evpBytesToKey({
    required String passphrase,
    required List<int> salt,
    required int keyLen,
    required int ivLen,
  }) {
    final passBytes = utf8.encode(passphrase);
    var key = <int>[];
    var prev = <int>[];

    while (key.length < keyLen + ivLen) {
      final md5Hash = md5Convert([...prev, ...passBytes, ...salt]);
      key.addAll(md5Hash);
      prev = md5Hash;
    }

    return Tuple2(
      Uint8List.fromList(key.sublist(0, keyLen)),
      Uint8List.fromList(key.sublist(keyLen, keyLen + ivLen)),
    );
  }

  List<int> md5Convert(List<int> input) =>
      md5.convert(Uint8List.fromList(input)).bytes;


  Future<void> _checkBiometric() async {
    try {
      final isEnabled = await storage.read(key: "biometric_enabled").timeout(const Duration(seconds: 3));

      final isSupported = await auth.isDeviceSupported();
      final canCheck = await auth.canCheckBiometrics;
      final availableBiometrics = await auth.getAvailableBiometrics();

      final hasAnyBiometric = isSupported && canCheck && availableBiometrics.isNotEmpty;

      if (!hasAnyBiometric) {
        debugPrint("⏭ No biometrics available on device — skipping biometric auth.");
        await storage.delete(key: "biometric_enabled");
        if (mounted) {
          BiometricSession.biometricPassed = false;
          setState(() => _authenticated = true);
        }
        return;
      }

      if (isEnabled == "true") {
        if (mounted) setState(() => _authenticated = false);
      } else {
        if (mounted) {
          BiometricSession.biometricPassed = false;
          setState(() => _authenticated = true);
        }
      }
    } catch (e) {
      debugPrint("⚠️ Biometric check failed: $e");
      if (mounted) {
        BiometricSession.biometricPassed = false;
        setState(() => _authenticated = true);
      }
    }
  }

  Future<String?> getDisplayName() async {
    return await storage.read(key: "display_name");
  }

  Widget companyLogoWidget(String? companyLogo, {double height = 80}) {
    if (companyLogo == null || companyLogo.isEmpty) {
      return Image.asset("assets/logo.jpeg", height: height);
    }

    if (companyLogo.startsWith("data:image")) {
      final parts = companyLogo.split(',');
      if (parts.length == 2) {
        try {
          final bytes = base64Decode(parts[1]);
          return Image.memory(Uint8List.fromList(bytes), height: height, fit: BoxFit.contain);
        } catch (e) {
          return Image.asset("assets/logo.jpeg", height: height);
        }
      } else {
        return Image.asset("assets/logo.jpeg", height: height);
      }
    }

    return Image.network(companyLogo, height: height);
  }

  Widget userAvatarWidget(String? userImage, {double radius = 40}) {
    if (userImage == null || userImage.isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: Colors.grey.shade200,
      );
    }

    if (userImage.startsWith("data:image")) {
      final parts = userImage.split(',');
      if (parts.length == 2) {
        try {
          final bytes = base64Decode(parts[1]);
          return CircleAvatar(
            radius: radius,
            backgroundImage: MemoryImage(Uint8List.fromList(bytes)),
            backgroundColor: Colors.grey.shade200,
          );
        } catch (e) {
          return CircleAvatar(
            radius: radius,
            backgroundImage: const AssetImage("assets/profile_placeholder.png"),
            backgroundColor: Colors.grey.shade200,
          );
        }
      } else {
        return CircleAvatar(
          radius: radius,
          backgroundImage: const AssetImage("assets/profile_placeholder.png"),
          backgroundColor: Colors.grey.shade200,
        );
      }
    }

    return CircleAvatar(
      radius: radius,
      backgroundImage: NetworkImage(userImage),
      backgroundColor: Colors.grey.shade200,
    );
  }


  @override
  Widget build(BuildContext context) {
    const backgroundColor = Colors.white;

    return Builder(
      builder: (context) {
        if (_authenticated == null) {
          final companyLogo = userData?['cLogo'];

          return Scaffold(
            body: Stack(
              fit: StackFit.expand,
              children: [
                SvgPicture.asset(
                  "assets/background.svg",
                  fit: BoxFit.cover,
                ),
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (companyLogo != null && companyLogo.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 24.0),
                          child: companyLogoWidget(companyLogo, height: 120),
                        ),
                      const CircularProgressIndicator(color: Colors.teal),
                      const SizedBox(height: 16),
                      const Text(
                        "Setting things up...",
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        } else if (_authenticated == false) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (_biometricPromptShown) return;
            _biometricPromptShown = true;

            final isEnabled = await storage.read(key: "biometric_enabled");
            if (isEnabled == "true") {
              final success = await authenticateUser();
              if (success) {
                BiometricSession.biometricPassed = true;
                if (mounted) setState(() => _authenticated = true);
              } else {
                _biometricPromptShown = false;
              }
            }
          });
          final userName = userData?['uName'];
          final userImage = userData?['uImage'];
          final companyLogo = userData?['cLogo'];
          final companyName = userData?['cName'];

          DateTime? lastBackPress;

          return WillPopScope(
            onWillPop: () async {
              final now = DateTime.now();
              if (lastBackPress == null || now.difference(lastBackPress!) > const Duration(seconds: 2)) {
                lastBackPress = now;
                Fluttertoast.showToast(msg: "Press again to exit");
                return false;
              }

              const platform = MethodChannel('app.channel.shared.data');
              await platform.invokeMethod('closeAppCompletely');
              return true;
            },
            child: Scaffold(
              body: Stack(
                fit: StackFit.expand,
                children: [
                  SvgPicture.asset(
                    "assets/background.svg",
                    fit: BoxFit.cover,
                  ),
                  SafeArea(
                    child: _isLoadingUserData ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: Colors.teal,),
                          SizedBox(height: 16),
                          Text(
                            "Loading, please wait...",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: Colors.white,
                            ),
                          )
                        ],
                      ),
                    ) : Column(
                      children: [
                        if (companyLogo != null && companyLogo.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 24.0),
                            child: companyLogoWidget(companyLogo, height: 150),
                          )
                        else
                          const SizedBox(height: 80),
                        Expanded(
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const SizedBox(height: 80),
                                if (userImage != null && userImage.isNotEmpty)
                                  userAvatarWidget(userImage, radius: 50),
                                const SizedBox(height: 12),
                                Text(
                                  userName ?? '',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.tealAccent.shade700,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 20, vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  icon: const Icon(Icons.login),
                                  onPressed: () {
                                    setState(() => _authenticated = true);
                                  },
                                  label: const Text("Login with ID & Password"),
                                ),
                                const SizedBox(height: 12),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.black87,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 20, vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  icon: const Icon(Icons.fingerprint),
                                  onPressed: () async {
                                    _biometricPromptShown = true;
                                    final retry = await authenticateUser();
                                    if (retry) {
                                      BiometricSession.biometricPassed = true;
                                      if (mounted) setState(() => _authenticated = true);
                                    } else {
                                      _biometricPromptShown = false;
                                    }
                                  },
                                  label: const Text("Login with Fingerprint"),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        } else {
          return Scaffold(
            backgroundColor: backgroundColor,
            body: widget.child,
          );
        }
      },
    );
  }
}

class Tuple2<T1, T2> {
  final T1 item1;
  final T2 item2;
  Tuple2(this.item1, this.item2);
}