import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart';
import 'package:mcapps/login.dart';

class UserDrawer extends StatefulWidget {
  final Map<String, dynamic> userData;

  const UserDrawer({super.key, required this.userData});

  @override
  State<UserDrawer> createState() => _UserDrawerState();
}

class _UserDrawerState extends State<UserDrawer> {
  File? _profileImage;

  @override
  void initState() {
    super.initState();
    _loadProfileImage();
  }

  Future<void> _loadProfileImage() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? path = prefs.getString('profileImage');
    if (path != null && File(path).existsSync()) {
      setState(() {
        _profileImage = File(path);
      });
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);

    if (pickedFile != null) {
      final directory = await getApplicationDocumentsDirectory();
      final fileName = basename(pickedFile.path);
      final savedImage = await File(pickedFile.path).copy('${directory.path}/$fileName');

      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('profileImage', savedImage.path);

      setState(() {
        _profileImage = savedImage;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
              ),
              child: Column(
                children: [
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 40,
                        backgroundColor: Colors.white12,
                        backgroundImage: _profileImage != null ? FileImage(_profileImage!) : null,
                        child: _profileImage == null
                            ? const Icon(Icons.person, size: 40, color: Colors.white70)
                            : null,
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: InkWell(
                          onTap: _pickImage,
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            padding: const EdgeInsets.all(4),
                            child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                          ),
                        ),
                      )
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.userData['displayname'] ?? 'User',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  Text(
                    widget.userData['mail'] ?? '',
                    style: const TextStyle(fontSize: 14, color: Colors.white70),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
                    child: Text(
                      'User Info',
                      style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
                    ),
                  ),
                  _buildInfoTile(Icons.business, "Company", widget.userData['company']),
                  _buildInfoTile(Icons.badge, "Title", widget.userData['title']),
                  _buildInfoTile(Icons.account_tree, "Department", widget.userData['department']),
                  const Divider(color: Colors.white24, height: 30),
                  ListTile(
                    leading: const Icon(Icons.logout, color: Colors.redAccent),
                    title: const Text(
                      'Logout',
                      style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
                    ),
                    onTap: () async {
                      SharedPreferences prefs = await SharedPreferences.getInstance();
                      await prefs.clear();
                      if (!mounted) return;
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const LoginPage()),
                        (route) => false,
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoTile(IconData icon, String label, String? value) {
    return ListTile(
      leading: Icon(icon, color: Colors.white),
      title: Text(
        value ?? 'Not available',
        style: const TextStyle(color: Colors.white, fontSize: 16),
      ),
      subtitle: Text(
        label,
        style: const TextStyle(color: Colors.white54, fontSize: 13),
      ),
    );
  }
}
