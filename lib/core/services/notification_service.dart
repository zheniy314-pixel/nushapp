import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Сервис push-уведомлений (входящие звонки, сообщения, конференции)
class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();

  static const _callChannelId   = 'nusha_calls';
  static const _msgChannelId    = 'nusha_messages';
  static const _confChannelId   = 'nusha_conferences';

  Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: _onTap,
    );

    // Создаём каналы Android
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(const AndroidNotificationChannel(
      _callChannelId, 'Звонки',
      description: 'Входящие звонки',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    ));
    await androidPlugin?.createNotificationChannel(const AndroidNotificationChannel(
      _msgChannelId, 'Сообщения',
      description: 'Новые сообщения',
      importance: Importance.high,
    ));
    await androidPlugin?.createNotificationChannel(const AndroidNotificationChannel(
      _confChannelId, 'Конференции',
      description: 'Приглашения в конференции',
      importance: Importance.high,
    ));
  }

  // Входящий звонок
  Future<void> showIncomingCall({
    required String callerName,
    required String callId,
    required String kind, // audio/video
  }) async {
    await _plugin.show(
      1,
      'Входящий ${kind == 'video' ? 'видео' : 'аудио'}звонок',
      callerName,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _callChannelId, 'Звонки',
          importance: Importance.max,
          priority: Priority.max,
          fullScreenIntent: true,
          category: AndroidNotificationCategory.call,
          actions: [
            const AndroidNotificationAction('reject', 'Отклонить', cancelNotification: true),
            const AndroidNotificationAction('answer', 'Ответить', cancelNotification: true),
          ],
        ),
        iOS: const DarwinNotificationDetails(
          categoryIdentifier: 'CALL',
          interruptionLevel: InterruptionLevel.critical,
        ),
      ),
      payload: 'call:$callId:$kind',
    );
  }

  // Новое сообщение
  Future<void> showMessage({
    required String senderName,
    required String chatId,
    required String preview,
    int badgeCount = 1,
  }) async {
    await _plugin.show(
      chatId.hashCode,
      senderName,
      preview,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _msgChannelId, 'Сообщения',
          importance: Importance.high,
          priority: Priority.high,
          number: badgeCount,
        ),
        iOS: DarwinNotificationDetails(
          badgeNumber: badgeCount,
          categoryIdentifier: 'MESSAGE',
        ),
      ),
      payload: 'message:$chatId',
    );
  }

  // Приглашение в конференцию
  Future<void> showConferenceInvite({
    required String hostName,
    required String roomCode,
    required String title,
  }) async {
    await _plugin.show(
      roomCode.hashCode,
      'Приглашение: $title',
      'От $hostName · Код: $roomCode',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _confChannelId, 'Конференции',
          importance: Importance.high,
          actions: [
            const AndroidNotificationAction('join', 'Войти', cancelNotification: true),
            const AndroidNotificationAction('decline', 'Отклонить', cancelNotification: true),
          ],
        ),
        iOS: const DarwinNotificationDetails(categoryIdentifier: 'CONFERENCE'),
      ),
      payload: 'conference:$roomCode',
    );
  }

  Future<void> cancelCall() => _plugin.cancel(1);
  Future<void> cancelAll() => _plugin.cancelAll();

  void _onTap(NotificationResponse r) {
    final payload = r.payload ?? '';
    // Routing будет выполнен через глобальный navigator key
    // TODO: подключить NavigatorService
  }
}
