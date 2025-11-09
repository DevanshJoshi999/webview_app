import 'package:banking_app_webview/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/svg.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:banking_app_webview/utils.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

class WebViewScreen extends StatefulWidget {
  final bool startFromDashboard;
  const WebViewScreen({super.key, this.startFromDashboard = false});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController _controller;
  bool _dialogShown = false;
  bool _pageLoaded = false;
  DateTime? _lastBackPress;
  String _currentUrl = "";

  @override
  void initState() {
    super.initState();

    _controller =
    WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000));
    if (_controller.platform is AndroidWebViewController) {
      AndroidWebViewController.enableDebugging(true);
      (_controller.platform as AndroidWebViewController)
        ..setTextZoom(100)
        ..setUseWideViewPort(true);
    }
    _controller
      ..addJavaScriptChannel(
        "UrlChange",
        onMessageReceived: (message) async {
          final msg = message.message;

          if (msg.startsWith("SAVE_CREDENTIALS::")) {
            final parts = msg.split("::");
            final loginUsername = parts[1];
            final password = parts[2];
            await storage.write(key: "login_username", value: loginUsername);
            await storage.write(key: "password", value: password);
            debugPrint("✅ Credentials saved: $loginUsername / $password");
            return;
          }

          if (msg.startsWith("USERNAME::")) {
            final displayName = msg.replaceFirst("USERNAME::", "");
            await storage.write(key: "display_name", value: displayName);
            debugPrint("✅ Captured display name: $displayName");
            return;
          }

          if (msg.startsWith("AD_DATA::")) {
            final encryptedAd = msg.replaceFirst("AD_DATA::", "");
            await storage.write(key: "ad", value: encryptedAd);
            debugPrint("✅ Stored encrypted ad value in secure storage");
            return;
          }


          setState(() {
            _currentUrl = msg;
          });
          debugPrint("Detected SPA URL: $_currentUrl");
          if (_currentUrl.contains("dashboard")) {
            final isBiometricSet = await storage.read(key: "biometric_enabled");
            final hasPromptBeenShown = await storage.read(key: "biometric_prompt_shown");
            if (isBiometricSet == null && hasPromptBeenShown != "true" && !_dialogShown && mounted) {
              _dialogShown = true;
              _showEnableBiometricDialog();
            }
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) async {
            setState(() {
              _currentUrl = url;
              _pageLoaded = true;
            });
            if (url.contains("dashboard")) {
              _controller.runJavaScript('''
              (function waitForUserName() {
                var userDiv = document.querySelector("div.col-12.text-center.font-bold");
                if (userDiv && userDiv.innerText.trim().length > 0) {
                  UrlChange.postMessage("USERNAME::" + userDiv.innerText.trim());
                } else {
                  setTimeout(waitForUserName, 500);
                }
              })();
            ''');
            }
            _controller.runJavaScript('''
              (function() {
                var meta = document.querySelector('meta[name=viewport]');
                if (!meta) {
                  meta = document.createElement('meta');
                  meta.name = "viewport";
                  document.head.appendChild(meta);
                }
                meta.content = "width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no";
              })();
            ''');
            _controller.runJavaScript('''
              (function() {
                document.body.style.zoom = "1.0";
                document.body.style.webkitTextSizeAdjust = "100%";
              })();
            ''');
            debugPrint("Page finished loading: $url");
            _controller.runJavaScript('''
              (function checkAdStorage() {
                try {
                  var adValue = localStorage.getItem('ad');
                  if (adValue && adValue.length > 0) {
                    UrlChange.postMessage("AD_DATA::" + adValue);
                  } else {
                    setTimeout(checkAdStorage, 1000);
                  }
                } catch (e) {
                  console.log("Error reading ad:", e);
                  setTimeout(checkAdStorage, 1000);
                }
              })();
            ''');
            final isBiometricEnabled = await storage.read(key: "biometric_enabled");
            if (isBiometricEnabled == "true" && BiometricSession.biometricPassed) {
              final credsUsername = await storage.read(key: "login_username");
              final credsPassword = await storage.read(key: "password");
              if (credsUsername != null && credsPassword != null) {
                final js = """
                  (function waitForInputs() {
                    const u = document.querySelector("#username")
                              || document.querySelector("input[formcontrolname='user_name']")
                              || document.querySelector("input[type='text']");
                    const p = document.querySelector("input[type='password']");
                    const btn = document.querySelector("button[type='submit']") || document.querySelector("button.p-button");
                  
                    if (u && p && btn) {
                      u.value = "$credsUsername";
                      p.value = "$credsPassword";
                  
              
                      ['input','change','blur'].forEach(e => {
                        u.dispatchEvent(new Event(e, { bubbles: true }));
                        p.dispatchEvent(new Event(e, { bubbles: true }));
                      });
                  
                      
                      btn.click();
                    } else {
                     
                      setTimeout(waitForInputs, 300);
                    }
                  })();
                """;
                _controller.runJavaScript(js);
              }
            }
            _controller.runJavaScript('''
              (function() {
                const form = document.querySelector("form");
                if (form && !form._listenerAdded) {
                  form._listenerAdded = true;
                  form.addEventListener("submit", function() {
                    const username = document.querySelector("#username")?.value 
                                  || document.querySelector("input[formcontrolname='user_name']")?.value 
                                  || "";
                    const password = document.querySelector("input[type='password']")?.value || "";
                    UrlChange.postMessage("SAVE_CREDENTIALS::" + username + "::" + password);
                  });
                }
              })();
            ''');
            _controller.runJavaScript('''
              (function() {
                function notifyFlutter() {
                  UrlChange.postMessage(window.location.href);
                }
                history.pushState = (f => function pushState(){
                  var ret = f.apply(this, arguments);
                  notifyFlutter();
                  return ret;
                })(history.pushState);
                history.replaceState = (f => function replaceState(){
                  var ret = f.apply(this, arguments);
                  notifyFlutter();
                  return ret;
                })(history.replaceState);
                window.addEventListener('popstate', notifyFlutter);
                notifyFlutter();
              })();
            ''');
          },
        ),
      )
      ..loadRequest(Uri.parse("https://netbanking.munimji.online/auth"));
  }

  void _showEnableBiometricDialog() async {
    final isSupported = await auth.isDeviceSupported();
    final canCheck = await auth.canCheckBiometrics;
    final availableBiometrics = await auth.getAvailableBiometrics();
    final hasAnyBiometric = isSupported && canCheck && availableBiometrics.isNotEmpty;
    final hasPromptBeenShown = await storage.read(key: "biometric_prompt_shown");

    if (!hasAnyBiometric || hasPromptBeenShown == "true") {
      debugPrint("⏩ Skipping biometric prompt — no biometrics enrolled or already prompted.");
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Enable Biometric Login?"),
        content: const Text(
          "You will be asked to verify now with your fingerprint for faster logins.",
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await storage.write(key: "biometric_prompt_shown", value: "true");
              await storage.delete(key: "biometric_enabled");

              if (mounted) {
                Navigator.pop(context);
                Future.delayed(const Duration(milliseconds: 300), () async {
                  final currentUrl = await _controller.currentUrl();
                  if (mounted) {
                    setState(() {
                      _currentUrl = currentUrl ?? "https://netbanking.munimji.online/dashboard";
                    });
                  }
                });
              }
            },
            child: const Text("No"),
          ),
          TextButton(
            onPressed: () async {
              final success = await authenticateUser();
              if (success) {
                await storage.write(key: "biometric_enabled", value: "true");
                await storage.write(key: "biometric_prompt_shown", value: "true");

                Fluttertoast.showToast(
                  msg: "Biometric login enabled successfully",
                  toastLength: Toast.LENGTH_SHORT,
                  gravity: ToastGravity.BOTTOM,
                  backgroundColor: Colors.green,
                  textColor: Colors.white,
                );
              } else {
                Fluttertoast.showToast(
                  msg: "Biometric verification failed or canceled",
                  toastLength: Toast.LENGTH_SHORT,
                  gravity: ToastGravity.BOTTOM,
                  backgroundColor: Colors.red,
                  textColor: Colors.white,
                );
                await storage.delete(key: "biometric_enabled");
              }

              await storage.write(key: "biometric_prompt_shown", value: "true");

              if (mounted) {
                Navigator.pop(context);
                Future.delayed(const Duration(milliseconds: 300), () async {
                  final currentUrl = await _controller.currentUrl();
                  if (mounted) {
                    setState(() {
                      _currentUrl = currentUrl ?? "https://netbanking.munimji.online/dashboard";
                    });
                  }
                });
              }
            },
            child: const Text("Yes"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        final now = DateTime.now();
        final isLoginScreen = _currentUrl.contains("auth") || _currentUrl.contains("login");
        final isDashboard = _currentUrl.contains("dashboard");

        if (isDashboard) {
          final shouldExit = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text("Exit", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),),
              content: const Text("Are you sure you want to exit?", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),),
              actions: [
                TextButton(
                  onPressed: () async {
                    Navigator.pop(context, false);
                    Future.delayed(const Duration(milliseconds: 300), () async {
                      final currentUrl = await _controller.currentUrl();
                      if (mounted) {
                        setState(() {
                          _currentUrl = currentUrl ?? "https://netbanking.munimji.online/dashboard";
                        });
                      }
                    });
                  },
                  child: const Text("NO", style: TextStyle(color: Colors.teal, fontSize: 18, fontWeight: FontWeight.w600),),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text("YES", style: TextStyle(color: Colors.teal, fontSize: 18, fontWeight: FontWeight.w600),),
                ),
              ],
            ),
          );

          if (shouldExit == true) {
            const platform = MethodChannel('app.channel.shared.data');
            await platform.invokeMethod('closeAppCompletely');
            return true;
          }
          return false;
        }

        if (isLoginScreen) {
          if (_lastBackPress == null || now.difference(_lastBackPress!) > const Duration(seconds: 2)) {
            _lastBackPress = now;
            Fluttertoast.showToast(msg: "Press again to exit");
            return false;
          }
          const platform = MethodChannel('app.channel.shared.data');
          await platform.invokeMethod('closeAppCompletely');
          return true;
        }

        if (await _controller.canGoBack()) {
          _controller.goBack();
          return false;
        }

        return true;
      },
      child: SafeArea(
        child: Scaffold(
          backgroundColor: Colors.white,
          body: Stack(
            children: [
              AnimatedOpacity(opacity: _pageLoaded ? 1 : 0, duration: const Duration(milliseconds: 400), child: WebViewWidget(controller: _controller)),
              if (!_pageLoaded)
                Stack(
                  fit: StackFit.expand,
                  children: [
                    SvgPicture.asset(
                      "assets/background.svg",
                      fit: BoxFit.cover,
                    ),
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          CircularProgressIndicator(color: Colors.teal),
                          SizedBox(height: 16),
                          Text(
                            "Loading, please wait...",
                            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}