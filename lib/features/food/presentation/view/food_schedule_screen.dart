import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:fitness_os/features/food/data/food_notification_scheduler.dart';
import 'package:fitness_os/features/food/domain/food_schedule_config.dart';

/// Screen for configuring meal schedule and reminders.
class FoodScheduleScreen extends StatefulWidget {
  const FoodScheduleScreen({super.key, this.scheduler});

  final FoodNotificationScheduler? scheduler;

  @override
  State<FoodScheduleScreen> createState() => _FoodScheduleScreenState();
}

class _FoodScheduleScreenState extends State<FoodScheduleScreen> {
  late FoodNotificationScheduler _scheduler;
  late FoodScheduleConfig _config;
  late bool _remindersEnabled;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _scheduler = widget.scheduler ?? GetIt.I<FoodNotificationScheduler>();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    setState(() => _isLoading = true);
    try {
      final config = await _scheduler.loadSchedule();
      final enabled = _scheduler.areRemindersEnabled();
      if (mounted) {
        setState(() {
          _config = config;
          _remindersEnabled = enabled;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveConfig() async {
    setState(() => _isSaving = true);
    try {
      await _scheduler.saveSchedule(_config);
      if (_remindersEnabled) {
        await _scheduler.enableReminders();
      } else {
        await _scheduler.disableReminders();
      }
      if (mounted) {
        setState(() => _isSaving = false);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    }
  }

  Future<void> _pickTime(
    String slot,
    TimeOfDayData current,
    void Function(TimeOfDayData) onChanged,
  ) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
    );

    if (picked != null) {
      onChanged(TimeOfDayData(hour: picked.hour, minute: picked.minute));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final theme = Theme.of(context);

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Meal Schedule')),
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation(colors.accent),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        title: const Text('Meal Schedule'),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _saveConfig,
            child: _isSaving
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(colors.accent),
                    ),
                  )
                : Text(
                    'Save',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.accent,
                    ),
                  ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Reminders toggle
          _buildSection(
            colors,
            theme,
            'Reminders',
            child: SwitchListTile(
              title: Text(
                'Enable reminders',
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.ink,
                ),
              ),
              subtitle: Text(
                'Get notified before meals',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.inkFaint,
                ),
              ),
              value: _remindersEnabled,
              onChanged: (value) {
                setState(() => _remindersEnabled = value);
              },
            ),
          ),

          const SizedBox(height: 24),

          // Lead time
          _buildSection(
            colors,
            theme,
            'Notification timing',
            child: ListTile(
              title: Text(
                'Notify before meal',
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.ink,
                ),
              ),
              trailing: DropdownButton<int>(
                value: _config.leadMinutes,
                items: const [
                  DropdownMenuItem(value: 5, child: Text('5 min')),
                  DropdownMenuItem(value: 10, child: Text('10 min')),
                  DropdownMenuItem(value: 15, child: Text('15 min')),
                  DropdownMenuItem(value: 30, child: Text('30 min')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _config = _config.copyWith(leadMinutes: value);
                    });
                  }
                },
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Meal times
          _buildSection(
            colors,
            theme,
            'Meal times',
            child: Column(
              children: [
                _buildMealTime(
                  colors,
                  theme,
                  'Breakfast',
                  'breakfast',
                  _config.breakfastTime,
                  (time) => setState(() {
                    _config = _config.copyWith(breakfastTime: time);
                  }),
                ),
                _buildMealTime(
                  colors,
                  theme,
                  'Lunch',
                  'lunch',
                  _config.lunchTime,
                  (time) => setState(() {
                    _config = _config.copyWith(lunchTime: time);
                  }),
                ),
                _buildMealTime(
                  colors,
                  theme,
                  'Dinner',
                  'dinner',
                  _config.dinnerTime,
                  (time) => setState(() {
                    _config = _config.copyWith(dinnerTime: time);
                  }),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
    FathomColors colors,
    ThemeData theme,
    String title, {
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: colors.bgElev,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: colors.inkFaint,
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }

  Widget _buildMealTime(
    FathomColors colors,
    ThemeData theme,
    String label,
    String slot,
    TimeOfDayData time,
    void Function(TimeOfDayData) onChanged,
  ) {
    final enabled = _config.enabledSlots.contains(slot);

    return CheckboxListTile(
      title: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: colors.ink,
              ),
            ),
          ),
          TextButton(
            onPressed: enabled
                ? () => _pickTime(slot, time, onChanged)
                : null,
            child: Text(
              _formatTime(time),
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: enabled ? colors.accent : colors.inkFaint,
              ),
            ),
          ),
        ],
      ),
      value: enabled,
      onChanged: (value) {
        setState(() {
          final newEnabled = Set<String>.from(_config.enabledSlots);
          if (value == true) {
            newEnabled.add(slot);
          } else {
            newEnabled.remove(slot);
          }
          _config = _config.copyWith(enabledSlots: newEnabled);
        });
      },
    );
  }

  String _formatTime(TimeOfDayData time) {
    final hour = time.hour;
    final minute = time.minute;
    final period = hour >= 12 ? 'PM' : 'AM';
    final hour12 = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '$hour12:${minute.toString().padLeft(2, '0')} $period';
  }
}
