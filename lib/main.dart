import 'package:banking_app_webview/services.dart';
import 'package:banking_app_webview/utils.dart';
import 'package:banking_app_webview/webview_screen.dart';
import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeSecureStorage();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nagarik Sharafi',
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        return MediaQuery(
          data: mediaQuery.copyWith(textScaler: TextScaler.noScaling),
          child: child!,
        );
      },
      home: BiometricGate(
        child: const WebViewScreen(startFromDashboard: false),
      ),
    );
  }
}