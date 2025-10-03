import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mcapps/login.dart';
import 'package:mcapps/mainpage.dart';
import 'package:mcapps/pages/message_detail_page.dart';

class Splashscreen extends StatefulWidget {
  final Map<String, dynamic>? notificationData;

  const Splashscreen({super.key, this.notificationData});

  @override
  State<Splashscreen> createState() => _SplashscreenState();
}

class _SplashscreenState extends State<Splashscreen>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );
    _fadeController.forward();

    Timer(const Duration(seconds: 3), _navigate);
  }

  Future<void> _navigate() async {
    // ✅ Case: Opened from terminated notification
    if (widget.notificationData != null) {
      final rawTimestamp = int.tryParse(widget.notificationData!['timestamp'] ?? '');
      final formatted = rawTimestamp != null
          ? DateFormat('MMMM d, y – hh:mm a').format(
              DateTime.fromMillisecondsSinceEpoch(rawTimestamp * 1000),
            )
          : 'Unknown Time';

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => MessageDetailPage(
            title: widget.notificationData!['title'] ?? 'No Title',
            message: widget.notificationData!['message'] ?? 'No Message',
            timestamp: formatted,
          ),
        ),
      );
      return;
    }

    // ✅ Otherwise: continue with login logic
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
    final loginTimeStr = prefs.getString('loginTimestamp');
    final userDataStr = prefs.getString('userData');

    if (isLoggedIn && loginTimeStr != null && userDataStr != null) {
      final loginTime = DateTime.tryParse(loginTimeStr);
      final isValid =
          loginTime != null && DateTime.now().difference(loginTime).inDays < 30;

      if (isValid) {
        final userData = jsonDecode(userDataStr);
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => Mainpage(userData: userData)),
        );
        return;
      } else {
        await prefs.clear();
      }
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0D47A1), Color(0xFF1976D2)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo with glow
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white.withOpacity(0.35),
                        blurRadius: 40,
                        spreadRadius: 6,
                      ),
                    ],
                  ),
                  child: Image.asset('assets/loading-logo.png', height: 110),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
