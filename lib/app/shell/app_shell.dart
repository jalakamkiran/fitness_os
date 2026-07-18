import 'package:flutter/material.dart';
import 'package:fitness_os/features/device_pairing/presentation/view/device_pairing_screen.dart';

/// Bottom-nav host: Home (pairing) + Vitals. Owns `/`.
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    this.vitalsBody,
  });

  /// Injected so U1 can ship a placeholder before the vitals feature lands.
  final Widget? vitalsBody;

  @override
  State<AppShell> createState() => AppShellState();
}

class AppShellState extends State<AppShell> {
  int _index = 0;

  void selectTab(int index) {
    if (index < 0 || index > 1) return;
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          const DevicePairingScreen(embedded: true),
          widget.vitalsBody ?? const _VitalsPlaceholder(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: selectTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.favorite_outline),
            selectedIcon: Icon(Icons.favorite),
            label: 'Vitals',
          ),
        ],
      ),
    );
  }
}

class _VitalsPlaceholder extends StatelessWidget {
  const _VitalsPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vitals')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Sleep and whole-day heart rate will appear here after Sync.\n'
            'No vitals stored yet.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
