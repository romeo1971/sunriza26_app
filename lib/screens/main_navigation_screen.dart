import 'package:flutter/material.dart';
import 'welcome_screen.dart';
import 'sunriza_content_screen_real.dart';
import 'ai_assistant_screen.dart';
import 'sunriza_real_screen.dart';

/// Hauptnavigation zwischen verschiedenen Screens
class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const WelcomeScreen(),
    const SunrizaContentScreenReal(),
    const AIAssistantScreen(),
    const SunrizaRealScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        backgroundColor: const Color(0xFF1A1A1A),
        selectedItemColor: const Color(0xFF00FF94),
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.info), label: 'Sunriza'),
          BottomNavigationBarItem(
            icon: Icon(Icons.smart_toy),
            label: 'KI-Assistent',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.web), label: 'Sunriza.com'),
        ],
      ),
    );
  }
}
