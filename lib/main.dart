import 'dart:async';

import 'package:banking_app_webview/new_internet_screen.dart';
import 'package:banking_app_webview/services.dart';
import 'package:banking_app_webview/utils.dart';
import 'package:banking_app_webview/webview_screen.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeSecureStorage();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late StreamSubscription _connectionSub;
  bool _hasInternet = true;

  @override
  void initState() {
    super.initState();
    _connectionSub = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      final connected = results.contains(ConnectivityResult.mobile) ||
          results.contains(ConnectivityResult.wifi);

      if (mounted) {
        setState(() => _hasInternet = connected);
      }
    });
  }

  @override
  void dispose() {
    _connectionSub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nagarik Sharafi',
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        return MediaQuery(data: mediaQuery.copyWith(textScaler: TextScaler.noScaling), child: child!);
      },
      home: _hasInternet ? BiometricGate(child: const WebViewScreen(startFromDashboard: false)) : const NoInternetScreen(),
    );
  }
}
