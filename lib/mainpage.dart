import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:mcapps/UserDrawer.dart';
import 'package:mcapps/pages/homepage.dart';

class Mainpage extends StatefulWidget {
  final Map<String, dynamic> userData;

  const Mainpage({super.key, required this.userData});

  @override
  State<Mainpage> createState() => _MainpageState();
}

class _MainpageState extends State<Mainpage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  int _selectedIndex = 0;

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();

    final user = widget.userData;

    _pages = [
      HomePage(displayName: user['displayname'] ?? 'User'),
      const Center(
        child: Text(
          'Search Page',
          style: TextStyle(fontSize: 24, color: Colors.white),
        ),
      ),
      const Center(
        child: Text(
          'Alerts Page',
          style: TextStyle(fontSize: 24, color: Colors.white),
        ),
      ),
      const Center(
        child: Text(
          'Profile Page',
          style: TextStyle(fontSize: 24, color: Colors.white),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey, // <-- Add this line
      drawer: UserDrawer(userData: widget.userData), // <-- Add the drawer
      extendBodyBehindAppBar: true,
      extendBody: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.account_circle, color: Colors.white, size: 28),
          onPressed: () {
            _scaffoldKey.currentState?.openDrawer(); // Open the drawer
          },
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Welcome to ',
              style: TextStyle(
                color: Colors.white,
                fontSize: 23,
                fontWeight: FontWeight.w500,
              ),
            ),
            Image.asset('assets/loading-logo.png', height: 40),
          ],
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1E3C72), Color(0xFF2A5298)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(child: _pages[_selectedIndex]),
      ),
      bottomNavigationBar: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
          child: BottomNavigationBar(
            backgroundColor: Colors.white.withOpacity(0.2),
            currentIndex: _selectedIndex,
            onTap: _onItemTapped,
            selectedItemColor: Colors.white,
            unselectedItemColor: Colors.white.withOpacity(0.6),
            showUnselectedLabels: true,
            type: BottomNavigationBarType.fixed,
            selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
              BottomNavigationBarItem(
                icon: Icon(Icons.search),
                label: 'Search',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.notifications),
                label: 'Alerts',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.person),
                label: 'Profile',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
