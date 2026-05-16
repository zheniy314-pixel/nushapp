import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';
import 'features/calculator/calculator_screen.dart';
import 'ui/theme/app_theme.dart';
import 'core/api/api_service.dart';
import 'core/services/socket_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/background_service.dart';
import 'core/services/global_notif_listener.dart';
import 'core/transport/transport_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Портретная + альбомная на всех платформах
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Инициализация сервисов
  await ApiService().init();
  await NotificationService().init();
  await TransportManager().init();

  // ── Фоновый сервис — держит Socket.IO живым даже на экране калькулятора ──
  // Запускается как Android Foreground Service, переживает любое состояние UI
  if (!kIsWeb) {
    await initBackgroundService();
  }

  // Проверяем авторизацию, обновляем токен если нужно, подключаем сокет
  const storage = FlutterSecureStorage();
  String? token = await storage.read(key: 'access_token');
  final refresh = await storage.read(key: 'refresh_token');

  // Если есть refresh token — обновим access token (устойчивая сессия)
  if (refresh != null && refresh.isNotEmpty) {
    try {
      final newTokens = await ApiService().refreshTokens(refresh);
      if (newTokens != null) {
        token = newTokens['accessToken'] as String?;
        await storage.write(key: 'access_token', value: token);
        await storage.write(key: 'refresh_token', value: newTokens['refreshToken'] as String?);
      }
    } catch (_) {
      // Сеть недоступна — используем старый токен
    }
  }

  if (token != null && token.isNotEmpty) {
    await ApiService().init();
    await SocketService().connect();
  }

  // ── Global notification listener: works even when calculator is shown ──────
  await GlobalNotifListener().init();

  runApp(const NushaApp());
}

class NushaApp extends StatefulWidget {
  const NushaApp({super.key});

  @override
  State<NushaApp> createState() => _NushaAppState();
}

class _NushaAppState extends State<NushaApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Калькулятор',               // Маскировка — видно в App Switcher
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: const CalculatorScreen(),      // ВСЕГДА начинаем с калькулятора
    );
  }
}
