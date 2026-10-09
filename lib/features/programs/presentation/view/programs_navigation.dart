import 'package:flutter/material.dart';

import 'package:fitness_os/features/programs/presentation/controller/programs_controller.dart';
import 'package:fitness_os/features/programs/presentation/view/programs_create_screen.dart';
import 'package:fitness_os/features/programs/presentation/view/programs_progress_screen.dart';
import 'package:fitness_os/features/programs/presentation/view/programs_proof_screen.dart';
import 'package:fitness_os/features/programs/presentation/view/programs_session_screen.dart';

/// Deep-links into Programs surfaces without requiring the `/programs` hub first.
abstract final class ProgramsNavigation {
  /// Opens today’s course session for [choreId].
  static Future<void> openSession(
    BuildContext context, {
    required ProgramsController controller,
    required String choreId,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProgramsSessionScreen(
          controller: controller,
          choreId: choreId,
        ),
      ),
    );
  }

  /// Opens proof for [milestoneId]. Returns false when [milestoneId] is null/empty
  /// and [fallbackChoreId] is also null (tested no-op).
  static Future<bool> openProof(
    BuildContext context, {
    required ProgramsController controller,
    String? milestoneId,
    String? fallbackChoreId,
  }) async {
    final mid = milestoneId?.trim();
    if (mid != null && mid.isNotEmpty) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ProgramsProofScreen(
            controller: controller,
            milestoneId: mid,
          ),
        ),
      );
      return true;
    }
    final choreId = fallbackChoreId?.trim();
    if (choreId != null && choreId.isNotEmpty) {
      await openSession(
        context,
        controller: controller,
        choreId: choreId,
      );
      return true;
    }
    return false;
  }

  static Future<void> openCreate(
    BuildContext context, {
    required ProgramsController controller,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProgramsCreateScreen(controller: controller),
      ),
    );
  }

  static Future<void> openOdyssey(
    BuildContext context, {
    required ProgramsController controller,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProgramsProgressScreen(controller: controller),
      ),
    );
  }
}
