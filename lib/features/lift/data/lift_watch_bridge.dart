import 'dart:async';

import 'package:fitness_os/core/huawei/huawei_bt_channel.dart';
import 'package:fitness_os/features/lift/domain/planned_session.dart';

class LiftReplyEvent {
  const LiftReplyEvent({
    required this.key,
    required this.text,
    required this.replyType,
    required this.rxAtMs,
    this.sentAtMs,
    this.kind = 'lift_reply',
  });

  final String kind;
  final String key;
  final String text;
  final int replyType;
  final int rxAtMs;
  final int? sentAtMs;
}

class LiftWatchBridge {
  LiftWatchBridge(this._channel, {Stream<HuaweiBtEvent>? events})
      : _events = events ?? _channel.events();

  final HuaweiBtChannel _channel;
  final Stream<HuaweiBtEvent> _events;
  bool _configured = false;

  Future<void> configure({required bool enabled}) async {
    await _channel.liftConfigure(enabled: enabled);
    _configured = enabled;
  }

  bool get isConfigured => _configured;

  Stream<LiftReplyEvent> get events async* {
    await for (final e in _events) {
      final map = switch (e) {
        UnknownEvent(:final raw) => raw,
        _ => null,
      };
      if (map == null) continue;
      final type = map['type'] as String?;
      if (type != 'lift_reply' &&
          type != 'lift_frame' &&
          type != 'lift_quick_replies' &&
          type != 'lift_enable_step' &&
          type != 'lift_notify_error') {
        continue;
      }
      if (type == 'lift_reply') {
        yield LiftReplyEvent(
          key: map['key'] as String? ?? '',
          text: map['text'] as String? ?? '',
          replyType: map['replyType'] as int? ?? 0,
          rxAtMs: map['rxAtMs'] as int? ?? 0,
        );
      } else {
        final text = switch (type) {
          'lift_notify_error' =>
            'error ${map['resultLabel']} code=${map['resultCode']} '
                'step=${map['step']}',
          'lift_enable_step' =>
            '${map['step']}: ${map['resultLabel'] ?? 'ok'} '
                'req=${map['requestHex']}',
          _ => map['tlvSummary'] as String? ?? map['responseHex'] as String? ?? '',
        };
        yield LiftReplyEvent(
          kind: type ?? 'lift_frame',
          key: map['step'] as String? ?? '',
          text: text,
          replyType: map['cmd'] as int? ?? map['resultCode'] as int? ?? 0,
          rxAtMs: map['rxAtMs'] as int? ?? 0,
        );
      }
    }
  }

  Future<Map<String, dynamic>> capabilities() =>
      _channel.liftCapabilities(enabled: _configured);

  Future<Map<String, dynamic>> sendSetNotification({
    required PlannedSet set,
    required String sessionId,
    required String title,
    required String body,
    int type = 0x7F,
    bool withReplyKey = true,
    String? category,
    String? sourceAppId,
  }) async {
    final key = set.notificationKey(sessionId);
    return _channel.liftSendTestNotification(
      enabled: _configured,
      title: title,
      sender: 'Fathom',
      body: body,
      withReplyKey: withReplyKey,
      type: type,
      key: key,
      category: category,
      sourceAppId: sourceAppId,
    );
  }

  Future<Map<String, dynamic>> enableWatchNotifications() =>
      _channel.liftEnableWatchNotifications();

  Future<Map<String, dynamic>> sendPlainTestNotification({
    required String title,
    required String body,
    required int type,
    String? sourceAppId,
  }) =>
      _channel.liftSendPlainTestNotification(
        enabled: _configured,
        title: title,
        body: body,
        type: type,
        sourceAppId: sourceAppId,
      );

  Future<void> removeLast() => _channel.liftRemove(enabled: _configured);

  Future<void> queryQuickReplies() =>
      _channel.liftQueryQuickReplies(enabled: _configured);

  Future<void> setQuickReplies(List<String> replies) =>
      _channel.liftSetQuickReplies(enabled: _configured, replies: replies);
}