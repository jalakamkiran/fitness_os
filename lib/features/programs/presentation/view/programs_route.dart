import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:fitness_os/app/routing/app_router.dart';
import 'package:fitness_os/features/programs/presentation/controller/programs_controller.dart';
import 'package:fitness_os/features/programs/presentation/view/programs_create_screen.dart';
import 'package:fitness_os/features/programs/presentation/view/programs_home_screen.dart';

/// Named route entry for Programs (`/programs`).
///
/// Shows create when no active program; otherwise active home.
class ProgramsRoute {
  static const String path = '/programs';

  static void register() {
    AppRouter.register(path, (context) {
      final controller = GetIt.I.isRegistered<ProgramsController>()
          ? GetIt.I<ProgramsController>()
          : ProgramsController.fromGetIt(GetIt.I);
      return ProgramsEntry(controller: controller);
    });
  }

  static void go(BuildContext context) {
    Navigator.pushNamed(context, path);
  }
}

/// Loads store and routes to create or active home.
class ProgramsEntry extends StatefulWidget {
  const ProgramsEntry({super.key, required this.controller});

  final ProgramsController controller;

  @override
  State<ProgramsEntry> createState() => _ProgramsEntryState();
}

class _ProgramsEntryState extends State<ProgramsEntry> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    widget.controller.load();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    if (c.loading && c.active == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (c.hasActive) {
      return ProgramsHomeScreen(controller: c);
    }
    return ProgramsCreateScreen(controller: c);
  }
}
