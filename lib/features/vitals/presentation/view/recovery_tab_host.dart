import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:fitness_os/core/di/injector.dart';
import 'package:fitness_os/features/food/presentation/view/food_tab_screen.dart';
import 'package:fitness_os/features/vitals/domain/repositories/vitals_repository.dart';
import 'package:fitness_os/features/vitals/presentation/bloc/vitals_bloc.dart';
import 'package:fitness_os/features/vitals/presentation/bloc/vitals_event.dart';
import 'package:fitness_os/features/vitals/presentation/view/sleep_tab_screen.dart';
import 'package:fitness_os/features/vitals/presentation/view/vitals_screen.dart';
import 'package:fitness_os/features/vitals/presentation/widgets/recovery_subtabs.dart';

/// Recovery bottom-tab host: shared [VitalsBloc] + Vitals | Sleep subtabs.
class RecoveryTabHost extends StatelessWidget {
  const RecoveryTabHost({super.key, this.bloc, this.repository});

  /// Optional override for widget tests.
  final VitalsBloc? bloc;

  /// Optional repository override (Sleep list extras / tests).
  final VitalsRepository? repository;

  @override
  Widget build(BuildContext context) {
    final override = bloc;
    final body = _RecoveryView(repository: repository);
    if (override != null) {
      return BlocProvider.value(
        value: override,
        child: body,
      );
    }
    return BlocProvider(
      create: (_) => sl<VitalsBloc>()..add(const VitalsStarted()),
      child: body,
    );
  }
}

class _RecoveryView extends StatefulWidget {
  const _RecoveryView({this.repository});

  final VitalsRepository? repository;

  @override
  State<_RecoveryView> createState() => _RecoveryViewState();
}

class _RecoveryViewState extends State<_RecoveryView> {
  RecoverySubtab _subtab = RecoverySubtab.sleep;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recovery',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: colors.ink,
              ),
            ),
            Text(
              'Recovery · GT5',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.inkFaint,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: RecoverySubtabs(
              selected: _subtab,
              onSelected: (tab) => setState(() => _subtab = tab),
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _subtab == RecoverySubtab.vitals
                  ? 0
                  : _subtab == RecoverySubtab.sleep
                      ? 1
                      : 2,
              children: [
                const VitalsScreen(embedded: true),
                SleepTabScreen(repository: widget.repository),
                const FoodTabScreen(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}