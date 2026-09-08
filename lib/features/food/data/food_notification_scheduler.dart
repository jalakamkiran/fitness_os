import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import 'package:fitness_os/features/device_pairing/domain/gate_a_prefs.dart';
import 'package:fitness_os/features/food/domain/food_capture_intent.dart';
import 'package:fitness_os/features/food/domain/food_schedule_config.dart';
import 'package:fitness_os/features/food/data/food_meal_store.dart';

/// Notification scheduler for meal reminders.
///
/// - Uses inexact scheduling (AndroidScheduleMode.inexactAllowWhileIdle)
/// - Stable notification IDs per slot
/// - Reschedules on config change / boot
/// - After ≥1 meal logged for a slot today, suppresses that slot's reminder for today
class FoodNotificationScheduler {
  FoodNotificationScheduler({
    required SharedPreferences prefs,
    required FoodMealStore store,
    FlutterLocalNotificationsPlugin? pluginOverride,
  })  : _prefs = prefs,
        _store = store,
        _plugin = pluginOverride ?? FlutterLocalNotificationsPlugin();

  final SharedPreferences _prefs;
  final FoodMealStore _store;
  final FlutterLocalNotificationsPlugin _plugin;

  static const _channelId = 'meal_reminders';
  static const _channelName = 'Meal Reminders';
  static const _channelDescription = 'Notifications for upcoming meals';

  // Stable notification IDs per slot
  static const _notifIdBreakfast = 1001;
  static const _notifIdLunch = 1002;
  static const _notifIdDinner = 1003;
  static const _notifIdSnack1 = 1011;
  static const _notifIdSnack2 = 1012;

  /// Initialize plugin. Call once at bootstrap.
  Future<void> initialize({
    required void Function(NotificationResponse) onNotificationTap,
  }) async {
    if (!Platform.isAndroid) return; // iOS not in scope

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: onNotificationTap,
    );
  }

  /// Load schedule config from prefs.
  Future<FoodScheduleConfig> loadSchedule() async {
    final json = _prefs.getString(GateAPrefs.foodScheduleJson);
    if (json == null || json.isEmpty) return FoodScheduleConfig();
    try {
      return FoodScheduleConfig.fromJsonString(json);
    } catch (_) {
      return FoodScheduleConfig();
    }
  }

  /// Save schedule config and reschedule notifications.
  Future<void> saveSchedule(FoodScheduleConfig config) async {
    await _prefs.setString(GateAPrefs.foodScheduleJson, config.toJsonString());
    await rescheduleAll();
  }

  /// Check if reminders are globally enabled.
  bool areRemindersEnabled() {
    return _prefs.getBool(GateAPrefs.foodRemindersEnabled) ?? false;
  }

  /// Enable reminders globally (requires POST_NOTIFICATIONS permission).
  Future<void> enableReminders() async {
    await _prefs.setBool(GateAPrefs.foodRemindersEnabled, true);
    await rescheduleAll();
  }

  /// Disable reminders globally (cancel all scheduled).
  Future<void> disableReminders() async {
    await _prefs.setBool(GateAPrefs.foodRemindersEnabled, false);
    await cancelAll();
    FoodCaptureIntent.clearPending();
  }

  /// Reschedule all enabled slots based on current config.
  Future<void> rescheduleAll() async {
    await cancelAll();

    if (!areRemindersEnabled()) return;

    final config = await loadSchedule();
    final now = DateTime.now();
    final today = _formatDayKey(now);

    // Check which slots already have meals logged today
    final todayMeals = await _store.loadDay(today);
    final loggedSlots = todayMeals.map((m) => m.slot).toSet();

    if (config.enabledSlots.contains('breakfast') && !loggedSlots.contains('breakfast')) {
      await _scheduleSlot('breakfast', config.breakfastTime, config.leadMinutes, _notifIdBreakfast);
    }

    if (config.enabledSlots.contains('lunch') && !loggedSlots.contains('lunch')) {
      await _scheduleSlot('lunch', config.lunchTime, config.leadMinutes, _notifIdLunch);
    }

    if (config.enabledSlots.contains('dinner') && !loggedSlots.contains('dinner')) {
      await _scheduleSlot('dinner', config.dinnerTime, config.leadMinutes, _notifIdDinner);
    }

    // Snacks (optional)
    for (var i = 0; i < config.snackTimes.length && i < 2; i++) {
      final slotKey = 'snack${i + 1}';
      if (config.enabledSlots.contains(slotKey) && !loggedSlots.contains(slotKey)) {
        final notifId = i == 0 ? _notifIdSnack1 : _notifIdSnack2;
        await _scheduleSlot(slotKey, config.snackTimes[i], config.leadMinutes, notifId);
      }
    }
  }

  /// Cancel a specific slot's notification after meal logged.
  Future<void> cancelSlotForToday(String slot) async {
    final notifId = _notifIdForSlot(slot);
    if (notifId != null) {
      await _plugin.cancel(notifId);
    }
  }

  /// Cancel all scheduled notifications.
  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }

  Future<void> _scheduleSlot(
    String slot,
    TimeOfDayData mealTime,
    int leadMinutes,
    int notifId,
  ) async {
    final now = tz.TZDateTime.now(tz.local);
    
    // Calculate reminder time (meal time - lead)
    var scheduledTime = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      mealTime.hour,
      mealTime.minute,
    ).subtract(Duration(minutes: leadMinutes));

    // If time has passed today, schedule for tomorrow
    if (scheduledTime.isBefore(now)) {
      scheduledTime = scheduledTime.add(const Duration(days: 1));
    }

    final title = _slotDisplayName(slot);
    final timeStr = _formatTime(mealTime);
    final body = timeStr;

    await _plugin.zonedSchedule(
      notifId,
      title,
      body,
      scheduledTime,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.high,
          priority: Priority.high,
          visibility: NotificationVisibility.private,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: '$slot|${_formatDayKey(scheduledTime)}',
    );
  }

  int? _notifIdForSlot(String slot) {
    switch (slot) {
      case 'breakfast':
        return _notifIdBreakfast;
      case 'lunch':
        return _notifIdLunch;
      case 'dinner':
        return _notifIdDinner;
      case 'snack1':
        return _notifIdSnack1;
      case 'snack2':
        return _notifIdSnack2;
      default:
        return null;
    }
  }

  String _slotDisplayName(String slot) {
    switch (slot) {
      case 'breakfast':
        return 'Breakfast reminder';
      case 'lunch':
        return 'Lunch reminder';
      case 'dinner':
        return 'Dinner reminder';
      case 'snack1':
      case 'snack2':
        return 'Snack reminder';
      default:
        return 'Meal reminder';
    }
  }

  String _formatTime(TimeOfDayData time) {
    final hour = time.hour;
    final minute = time.minute;
    final period = hour >= 12 ? 'PM' : 'AM';
    final hour12 = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '$hour12:${minute.toString().padLeft(2, '0')} $period';
  }

  String _formatDayKey(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }
}
