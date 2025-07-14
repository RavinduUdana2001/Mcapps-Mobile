import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mcapps/mainpage.dart';

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

  Future<void> _checkAutoLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
    final loginTimeStr = prefs.getString('loginTimestamp');
    final userDataStr = prefs.getString('userData');

    if (isLoggedIn && loginTimeStr != null && userDataStr != null) {
      final loginTime = DateTime.tryParse(loginTimeStr);
      if (loginTime != null &&
          DateTime.now().difference(loginTime).inDays < 30) {
        final userData = jsonDecode(userDataStr);
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
      final response = await http.post(
        Uri.parse('https://test.mchostlk.com/AD.php'),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {
          'username': username,
          'password': password,
          'company_name': company,
        },
      );

      if (response.statusCode != 200) {
        _showSnackBar("Server error: ${response.statusCode}");
        return;
      }

      final data = jsonDecode(response.body);

      if (data['error'] != null) {
        _showSnackBar(data['error']);
      } else {
        // ✅ Save session data for 30 days
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('isLoggedIn', true);
        await prefs.setString('loginTimestamp', DateTime.now().toIso8601String());
        await prefs.setString('userData', jsonEncode(data));

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => Mainpage(userData: data)),
        );
      }
    } catch (e) {
      _showSnackBar("Connection error: $e");
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    // 👇 You can leave the rest of the build method unchanged
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
                          border: Border.all(color: Colors.white.withOpacity(0.25)),
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
}
