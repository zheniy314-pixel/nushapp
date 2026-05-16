import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'socket_service.dart';

/// Global notification listener — persists across ALL navigation.
/// Works even when calculator screen is shown or app is minimized.
class GlobalNotifListener {
  static final _instance = GlobalNotifListener._();
  factory GlobalNotifListener() => _instance;
  GlobalNotifListener._();

  final _notif   = FlutterLocalNotificationsPlugin();
  final _socket  = SocketService();
  final _storage = const FlutterSecureStorage();

  StreamSubscription? _subMsg;
  StreamSubscription? _subCall;
  String? _myUserId;

  int _disguiseIdx = 0;
  static const _apps = ['YouTube', 'Gmail', 'LinkedIn', 'Telegram', 'WhatsApp', 'Maps'];

  Future<void> init() async {
    _myUserId = await _storage.read(key: 'user_id');

    await _notif.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ));

    final android = _notif.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      'nusha_bg_msg', 'Сообщения', description: 'Фоновые уведомления', importance: Importance.high,
    ));
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      'nusha_calls', 'Звонки', description: 'Входящие звонки', importance: Importance.max,
    ));

    _listen();
  }

  void _listen() {
    _subMsg?.cancel();
    _subCall?.cancel();

    _subMsg = _socket.onMessageNew.listen((data) {
      final msg      = data['message'] as Map? ?? {};
      final senderId = (msg['senderId'] ?? msg['sender'] ?? '').toString();
      // Never notify about own messages
      if (senderId.isNotEmpty && senderId == _myUserId) return;

      final sender = (data['senderName'] ?? 'Нуша').toString();
      final text   = (msg['text']?.toString() ?? '').isNotEmpty
          ? msg['text'].toString() : '📎 Медиа';
      final app = _apps[_disguiseIdx++ % _apps.length];

      _notif.show(
        (data['chatId']?.hashCode ?? 1),
        app,
        '$sender: $text',
        NotificationDetails(android: AndroidNotificationDetails(
          'nusha_bg_msg', 'Сообщения',
          icon: '@mipmap/ic_launcher',
          importance: Importance.high, priority: Priority.high,
          autoCancel: true, playSound: true,
        )),
      );
    });

    _subCall = _socket.onCallIncoming.listen((data) {
      final from    = (data['fromName'] ?? 'Звонок').toString();
      final isVideo = data['video'] == true;
      _notif.show(
        0,
        '$from звонит...',
        isVideo ? '📹 Видеозвонок' : '📞 Аудиозвонок',
        const NotificationDetails(android: AndroidNotificationDetails(
          'nusha_calls', 'Звонки',
          icon: '@mipmap/ic_launcher',
          importance: Importance.max, priority: Priority.max,
          fullScreenIntent: true, autoCancel: false, ongoing: true,
          category: AndroidNotificationCategory.call,
        )),
      );
    });
  }

  /// Call this after successful login / token refresh
  void updateUserId(String uid) {
    _myUserId = uid;
  }

  /// Refresh userId from storage (call if unsure)
  Future<void> refreshUserId() async {
    _myUserId = await _storage.read(key: 'user_id');
  }

  void dispose() {
    _subMsg?.cancel();
    _subCall?.cancel();
  }
}
