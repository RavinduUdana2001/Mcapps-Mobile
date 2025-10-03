import 'dart:convert';
import 'dart:ui';
import 'dart:async'; // ⬅ for TimeoutException
import 'dart:io'; // ⬅ for SocketException
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mcapps/mainpage.dart';

// ✅ For token + device/app info
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  String? _selectedCompany = 'McLarens';
  final List<String> _companies = ['McLarens', 'GAC', 'M&D'];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _checkAutoLogin(); // Auto-login if already logged in within 30 days
  }

  // ------------------------------
  // Normalizers for AD payload
  // ------------------------------
  String _extractUsername(Map<String, dynamic> d) {
    return (d['username'] ??
            d['user_name'] ??
            d['name'] ??
            d['displayName'] ??
            d['cn'] ??
            d['sAMAccountName'] ??
            d['uid'] ??
            '')
        .toString();
  }

  String? _extractEmail(Map<String, dynamic> d) {
    // AD usually provides 'mail'; sometimes UPN behaves like an email.
    final v =
        (d['email'] ??
        d['mail'] ?? // <-- primary for AD
        d['user_email'] ??
        d['UserEmail'] ??
        d['Email'] ??
        d['userPrincipalName'] ?? // AD UPN
        d['upn'] ??
        d['e_mail']);
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  Map<String, dynamic> _normalizeUserData(dynamic raw) {
    final map = Map<String, dynamic>.from(raw as Map);
    map['username'] = _extractUsername(map);
    final mail = _extractEmail(map);
    if (mail != null) map['email'] = mail; // ensure 'email' key exists
    return map;
  }

  Future<void> _checkAutoLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
    final loginTimeStr = prefs.getString('loginTimestamp');
    final userDataStr = prefs.getString('userData');

    if (isLoggedIn && loginTimeStr != null && userDataStr != null) {
      final loginTime = DateTime.tryParse(loginTimeStr);
      if (loginTime != null &&
          DateTime.now().difference(loginTime).inDays < 30) {
        final parsed = jsonDecode(userDataStr);

        // 🔄 Normalize (covers users saved before we added normalization)
        final userData = (parsed is Map)
            ? _normalizeUserData(parsed)
            : <String, dynamic>{};

        // persist normalized back so rest of app always sees email/username keys
        await prefs.setString('userData', jsonEncode(userData));

        // 🔔 After auto-login, send token with logged user's details
        await _syncPushTokenAfterLogin(userData);

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => Mainpage(userData: userData)),
        );
      } else {
        await prefs.clear(); // Session expired
      }
    }
  }

  Future<void> _login() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final company = _selectedCompany;

    if (username.isEmpty || password.isEmpty || company == null) {
      _showSnackBar("Please fill in all fields");
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await http
          .post(
            Uri.parse('https://test.mchostlk.com/AD.php'),
            headers: {"Content-Type": "application/x-www-form-urlencoded"},
            body: {
              'username': username,
              'password': password,
              'company_name': company,
            },
          )
          .timeout(const Duration(seconds: 15)); // ⬅ request timeout

      if (response.statusCode != 200) {
        await _showErrorDialog(
          title: "Server Unavailable",
          message:
              "We’re having trouble signing you in right now. (Code: ${response.statusCode})\nPlease try again in a moment.",
          icon: Icons.cloud_off,
        );
        return;
      }

      dynamic data;
      try {
        data = jsonDecode(response.body);
        // 👀 See what keys AD returned so we can tweak extractors if needed
        if (data is Map) {
          print('🔎 Login response keys: ${data.keys.toList()}');
        } else {
          print('🔎 Login response type: ${data.runtimeType}');
        }
      } catch (_) {
        await _showErrorDialog(
          title: "Unexpected Response",
          message:
              "We couldn’t read the server response. Please try again shortly.",
          icon: Icons.warning_amber_rounded,
        );
        return;
      }

      if (data is Map && data['error'] != null) {
        await _showErrorDialog(
          title: "Sign-in Failed",
          message: data['error'].toString(),
          icon: Icons.error_outline,
        );
      } else {
        // ✅ Normalize the user data (map AD 'mail' -> 'email', etc.)
        final normalized = (data is Map)
            ? _normalizeUserData(data)
            : <String, dynamic>{};

        // ✅ Save session for 30 days
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('isLoggedIn', true);
        await prefs.setString(
          'loginTimestamp',
          DateTime.now().toIso8601String(),
        );
        await prefs.setString('userData', jsonEncode(normalized));

        // 🔔 ONLY NOW send the token with username/email
        await _syncPushTokenAfterLogin(normalized);

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => Mainpage(userData: normalized)),
        );
      }
    } on SocketException {
      await _showNetworkIssueDialog();
    } on TimeoutException {
      await _showNetworkIssueDialog();
    } catch (_) {
      await _showErrorDialog(
        title: "Something Went Wrong",
        message: "An unexpected error occurred. Please try again.",
        icon: Icons.error_outline,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // ---------- Attractive Modals ----------

  Future<void> _showNetworkIssueDialog() async {
    return _showGlassDialog(
      icon: Icons.wifi_off_rounded,
      title: "No Internet Connection",
      message:
          "Please check your connection and try again.\n\nTips:\n• Turn on Wi-Fi or Mobile Data\n• Disable Airplane Mode\n• Try again in a few seconds",
      primaryText: "Retry",
      onPrimary: () {
        Navigator.of(context).pop();
        _login();
      },
      secondaryText: "Close",
    );
  }

  Future<void> _showErrorDialog({
    required String title,
    required String message,
    required IconData icon,
  }) async {
    return _showGlassDialog(
      icon: icon,
      title: title,
      message: message,
      primaryText: "OK",
      onPrimary: () => Navigator.of(context).pop(),
    );
  }

  Future<void> _showGlassDialog({
    required IconData icon,
    required String title,
    required String message,
    String primaryText = "OK",
    VoidCallback? onPrimary,
    String? secondaryText,
    VoidCallback? onSecondary,
  }) async {
    if (!mounted) return;
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: AlertDialog(
                elevation: 0,
                backgroundColor: Colors.white.withOpacity(0.12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: BorderSide(color: Colors.white.withOpacity(0.2)),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 22,
                ),
                titlePadding: const EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 20,
                  bottom: 8,
                ),
                title: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(icon, color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  ],
                ),
                content: Text(
                  message,
                  style: const TextStyle(color: Colors.white70, fontSize: 14.5),
                ),
                actionsPadding: const EdgeInsets.only(
                  left: 16,
                  right: 16,
                  bottom: 14,
                ),
                actions: [
                  if (secondaryText != null)
                    TextButton(
                      onPressed: onSecondary ?? () => Navigator.of(ctx).pop(),
                      child: Text(
                        secondaryText,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                  ElevatedButton(
                    onPressed: onPrimary ?? () => Navigator.of(ctx).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1976D2),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      primaryText,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // 👇 unchanged UI
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1976D2), Color(0xFF0D47A1)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset('assets/loading-logo.png', height: 100),
                  const SizedBox(height: 40),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(32),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                      child: Container(
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.white.withOpacity(0.2),
                              Colors.white.withOpacity(0.05),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(32),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.25),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            const Text(
                              "Welcome Back",
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              "Sign in to continue",
                              style: TextStyle(
                                fontSize: 15,
                                color: Colors.white60,
                              ),
                            ),
                            const SizedBox(height: 30),
                            _buildInputField(
                              icon: Icons.person,
                              hint: "Username",
                              controller: _usernameController,
                            ),
                            const SizedBox(height: 20),
                            _buildInputField(
                              icon: Icons.lock,
                              hint: "Password",
                              controller: _passwordController,
                              isPassword: true,
                            ),
                            const SizedBox(height: 20),
                            _buildDropdown(),
                            const SizedBox(height: 30),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _login,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF1976D2),
                                  foregroundColor: Colors.white,
                                  elevation: 6,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                ),
                                child: _isLoading
                                    ? const CircularProgressIndicator(
                                        color: Colors.white,
                                      )
                                    : const Text(
                                        "LOGIN",
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputField({
    required IconData icon,
    required String hint,
    required TextEditingController controller,
    bool isPassword = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: isPassword,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white54),
        prefixIcon: Icon(icon, color: Colors.white),
        filled: true,
        fillColor: Colors.white.withOpacity(0.12),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildDropdown() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedCompany,
          dropdownColor: const Color(0xFF1A237E),
          iconEnabledColor: Colors.white,
          isExpanded: true,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          items: _companies.map((company) {
            return DropdownMenuItem<String>(
              value: company,
              child: Text(company),
            );
          }).toList(),
          onChanged: (String? value) {
            setState(() {
              _selectedCompany = value;
            });
          },
          hint: const Text(
            'Select Company',
            style: TextStyle(color: Colors.white),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // 🔔 Push-token sync helper (after login / auto-login)
  //      Sends only when logged in and includes normalized username + email
  // ------------------------------------------------------------------
  Future<void> _syncPushTokenAfterLogin(Map<String, dynamic> userData) async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;

      final deviceInfo = DeviceInfoPlugin();
      String platform = Platform.isAndroid
          ? 'android'
          : (Platform.isIOS ? 'ios' : 'other');
      String deviceId = 'unknown_device';
      String model = 'unknown_model';

      if (Platform.isAndroid) {
        final info = await deviceInfo.androidInfo;
        deviceId = info.id ?? 'unknown_device'; // ✅ use id
        model = '${info.manufacturer} ${info.model}'.trim();
      } else if (Platform.isIOS) {
        final info = await deviceInfo.iosInfo;
        deviceId = info.identifierForVendor ?? 'unknown_device';
        model = '${info.name} ${info.model}'.trim();
      }

      final pkg = await PackageInfo.fromPlatform();
      final appVersion = pkg.version;

      final username = _extractUsername(userData);
      final email = _extractEmail(userData) ?? 'unknown@unknown';

      final payload = {
        "user_id": 123, // fixed as requested
        "username": username,
        "email": email,
        "device_id": deviceId,
        "fcm_token": token,
        "platform": platform,
        "model": model,
        "app_version": appVersion,
      };

      final res = await http.post(
        Uri.parse('https://office.mclarens.lk/api/orders/add_push_tokens'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(payload),
      );

      print('✅ [LOGIN] Response: ${res.statusCode} ${res.body}');
    } catch (e) {
      print('❌ [LOGIN] push token sync error: $e');
    }
  }
}
