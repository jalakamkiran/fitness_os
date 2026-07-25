import 'package:flutter/material.dart';
import 'package:fitness_os/features/device_pairing/presentation/view/device_pairing_screen.dart';
import 'package:fitness_os/features/workout_history/presentation/view/workout_history_screen.dart';

/// Bottom-nav host: Home | Vitals | Workouts. Owns `/`.
///
/// Home body stays pairing until the Home agent lands its now-state surface.
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    this.homeBody,
    this.vitalsBody,
    this.workoutsBody,
  });

  /// Injected for tests / gradual feature landing.
  final Widget? homeBody;
  final Widget? vitalsBody;
  final Widget? workoutsBody;

  @override
  State<AppShell> createState() => AppShellState();
}

class AppShellState extends State<AppShell> {
  int _index = 0;

  void selectTab(int index) {
    if (index < 0 || index > 2) return;
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          widget.homeBody ?? const DevicePairingScreen(embedded: true),
          widget.vitalsBody ?? const _VitalsPlaceholder(),
          widget.workoutsBody ?? const WorkoutHistoryScreen(),
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
          NavigationDestination(
            icon: Icon(Icons.list_alt_outlined),
            selectedIcon: Icon(Icons.list_alt),
            label: 'Workouts',
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
