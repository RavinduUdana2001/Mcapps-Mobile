import 'package:flutter/material.dart';
import 'package:mcapps/login.dart';
import 'package:mcapps/splashscreen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized(); // ✅ Necessary before using SharedPreferences

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Splashscreen(),
    );
  }
}
