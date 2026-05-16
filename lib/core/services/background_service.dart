// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../config/app_config.dart';

// ─── Notification channel IDs ───────────────────────────────────────────────
const _kMsgChannelId   = 'nusha_messages_bg';
const _kCallChannelId  = 'nusha_calls';
const _kFgChannelId    = 'nusha_fg_service';

// Disguise app names for masked notifications
const _kDisguiseApps = ['YouTube', 'Gmail', 'WhatsApp', 'Telegram', 'Maps'];
int _disguiseIdx = 0;

// ─── Init: call this from main() BEFORE runApp ───────────────────────────────
Future<void> initBackgroundService() async {
  final service = FlutterBackgroundService();

  // Android notification channel for the foreground service itself
  const fgChannel = AndroidNotificationChannel(
    _kFgChannelId,
    'Фоновый сервис',
    description: 'Работает в фоне',
    importance: Importance.low,
    showBadge: false,
    playSound: false,
  );
  const msgChannel = AndroidNotificationChannel(
    _kMsgChannelId,
    'Сообщения',
    description: 'Новые сообщения',
    importance: Importance.high,
  );
  const callChannel = AndroidNotificationChannel(
    _kCallChannelId,
    'Звонки',
    description: 'Входящие звонки',
    importance: Importance.max,
  );

  final plugin = FlutterLocalNotificationsPlugin();
  final android = plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  await android?.createNotificationChannel(fgChannel);
  await android?.createNotificationChannel(msgChannel);
  await android?.createNotificationChannel(callChannel);
  await plugin.initialize(const InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
  ));

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: _onStart,
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: _kFgChannelId,
      initialNotificationTitle: 'Калькулятор',
      initialNotificationContent: 'Работает в фоне',
      foregroundServiceNotificationId: 888,
      foregroundServiceTypes: [AndroidForegroundType.dataSync],
    ),
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: _onStart,
      onBackground: _onIosBackground,
    ),
  );

  await service.startService();
}

@pragma('vm:entry-point')
Future<bool> _onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

// ─── Background isolate entrypoint ──────────────────────────────────────────
@pragma('vm:entry-point')
void _onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  final notif = FlutterLocalNotificationsPlugin();
  await notif.initialize(const InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
  ));

  // Update foreground notification periodically so Android keeps us alive
  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((_) => service.setAsForegroundService());
    service.on('setAsBackground').listen((_) => service.setAsBackgroundService());
  }
  service.on('stopService').listen((_) => service.stopSelf());

  String? token;
  String? userId;
  io.Socket? socket;

  Future<void> connectSocket(String tok, String uid) async {
    token  = tok;
    userId = uid;

    socket?.dispose();
    socket = io.io(AppConfig.socketUrl, io.OptionBuilder()
        .setTransports(['websocket'])
        .setAuth({'token': token})
        .setReconnectionAttempts(999999)
        .setReconnectionDelay(3000)
        .build());

    // ── New message ──────────────────────────────────────────────────────────
    socket!.on('message:new', (raw) {
      try {
        final data       = raw as Map<dynamic, dynamic>;
        final senderName = data['senderName']?.toString() ?? 'Нуша';
        final msg        = data['message'] as Map<dynamic, dynamic>? ?? {};
        final text       = msg['text']?.toString() ?? '...';
        final chatId     = data['chatId']?.toString() ?? '';

        // Don't notify for own messages
        final senderId = msg['senderId']?.toString() ?? '';
        if (senderId == userId) return;

        // Rotate disguise app name
        final app = _kDisguiseApps[_disguiseIdx % _kDisguiseApps.length];
        _disguiseIdx++;

        notif.show(
          chatId.hashCode,
          app,
          '$senderName: $text',
          NotificationDetails(
            android: AndroidNotificationDetails(
              _kMsgChannelId,
              'Сообщения',
              icon: '@mipmap/ic_launcher',
              importance: Importance.high,
              priority: Priority.high,
              autoCancel: true,
              styleInformation: BigTextStyleInformation('$senderName: $text'),
            ),
          ),
        );
      } catch (_) {}
    });

    // ── Incoming call ────────────────────────────────────────────────────────
    socket!.on('call:incoming', (raw) {
      try {
        final data    = raw as Map<dynamic, dynamic>;
        final from    = data['fromName']?.toString() ?? 'Неизвестный';
        final isVideo = data['video'] == true;
        final callId  = data['callId']?.toString() ?? '';
        final kind    = isVideo ? 'Видеозвонок' : 'Аудиозвонок';

        notif.show(
          callId.hashCode,
          '$from звонит...',
          '$kind • Нажмите, чтобы ответить',
          NotificationDetails(
            android: AndroidNotificationDetails(
              _kCallChannelId,
              'Входящий звонок',
              icon: '@mipmap/ic_launcher',
              importance: Importance.max,
              priority: Priority.max,
              fullScreenIntent: true,
              autoCancel: false,
              ongoing: true,
              category: AndroidNotificationCategory.call,
              actions: [
                const AndroidNotificationAction(
                  'answer',
                  'Ответить',
                  cancelNotification: true,
                  showsUserInterface: true,
                ),
                const AndroidNotificationAction(
                  'decline',
                  'Отклонить',
                  cancelNotification: true,
                ),
              ],
            ),
          ),
        );
      } catch (_) {}
    });

    // ── Call ended — dismiss call notification ───────────────────────────────
    socket!.on('call:end', (raw) {
      try {
        final data   = raw as Map<dynamic, dynamic>;
        final callId = data['callId']?.toString() ?? '';
        notif.cancel(callId.hashCode);
      } catch (_) {}
    });

    socket!.onDisconnect((_) async {
      if (token != null) {
        await Future.delayed(const Duration(seconds: 3));
        connectSocket(token!, userId ?? '');
      }
    });
  }

  // ── Listen for token from main isolate when user logs in ──────────────────
  service.on('setToken').listen((data) async {
    if (data == null) return;
    final tok = data['token']?.toString();
    final uid = data['userId']?.toString();
    if (tok != null && tok.isNotEmpty && tok != token) {
      await connectSocket(tok, uid ?? '');
    }
  });

  // ── Keepalive timer ───────────────────────────────────────────────────────
  Timer.periodic(const Duration(seconds: 60), (_) async {
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(title: 'Калькулятор', content: 'Работает в фоне');
    }
  });
}

// ─── Call this from auth_screen after successful login ───────────────────────
// Sends token via IPC to the background isolate so it can connect the socket
Future<void> notifyBackgroundServiceLogin({
  required String token,
  required String userId,
}) async {
  try {
    final service = FlutterBackgroundService();
    final running = await service.isRunning();
    if (running) {
      service.invoke('setToken', {'token': token, 'userId': userId});
    }
  } catch (_) {}
}
