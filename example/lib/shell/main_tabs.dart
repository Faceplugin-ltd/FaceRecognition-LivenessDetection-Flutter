import 'package:flutter/material.dart';

import 'liveness_screen.dart';
import 'identify_screen.dart';
import 'people_screen.dart';
import 'settings_screen.dart';

/// Bottom tabs: Identify · People · Attribute · Settings · About — the same five as the
/// Android and iOS apps.
///
/// Identify and Attribute both own the camera, so only the visible one is kept alive;
/// the others keep their state across tab switches.
class MainTabs extends StatefulWidget {
  const MainTabs({super.key});

  @override
  State<MainTabs> createState() => _MainTabsState();
}

class _MainTabsState extends State<MainTabs> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _body(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.search_outlined),
            selectedIcon: Icon(Icons.search),
            label: 'Identity',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'People',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: 'Attribute',
          ),
          NavigationDestination(
            icon: Icon(Icons.remove_red_eye_outlined),
            selectedIcon: Icon(Icons.remove_red_eye),
            label: 'Liveness',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  Widget _body() {
    // The two camera tabs are rebuilt on entry rather than kept in an IndexedStack: two
    // live previews at once fight over the camera.
    switch (_index) {
      case 0:
        return const IdentifyScreen(key: ValueKey('identify'));
      case 2:
        return const IdentifyScreen(
          key: ValueKey('attribute'),
          attributeMode: true,
        );
      case 1:
        return const SafeArea(child: PeopleScreen());
      case 3:
        return const LivenessScreen(key: ValueKey('liveness'));
      default:
        return const SafeArea(child: SettingsScreen());
    }
  }
}
