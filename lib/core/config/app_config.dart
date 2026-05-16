/// Конфигурация приложения Nusha 3
class AppConfig {
  // ──────────────────────────── Сервер ────────────────────────────
  // DNS nushik.info пропагируется — пока используем прямой IP с nginx
  static const String baseUrl       = 'http://141.98.191.108';
  static const String apiUrl        = '$baseUrl/api';
  static const String socketUrl     = baseUrl;
  static const String domain        = 'nushik.info';
  static const String nikolayCoreUrl = 'http://127.0.0.1:3344';

  // ──────────────────────────── Приложение ────────────────────────
  static const String appName       = 'Калькулятор';      // маскировка
  static const String messengerName = 'Нуша';
  static const String nikolayName   = 'Николай';
  static const String bundleId      = 'com.nusha.messenger';
  static const String version       = '1.0.0';

  // ──────────────────────────── Конференции ───────────────────────
  static const int maxMobileParticipants  = 5;
  static const int maxDesktopParticipants = 50;
  static const int maxViewers             = 500;

  // ──────────────────────────── Медиа ─────────────────────────────
  static const int maxFileSizeMB          = 256;
  static const int maxImageSizeMB         = 50;
  static const int maxVideoSizeMB         = 256;
  static const int voiceNoteMaxSec        = 3600;

  // ──────────────────────────── Безопасность ───────────────────────
  static const int pinMinLength           = 4;
  static const int pinMaxLength           = 8;
  static const int sessionTimeoutMin      = 0;   // 0 = без таймаута

  // ──────────────────────────── Офлайн доставка ────────────────────
  static const int offlineTtlHours        = 72;
  static const int bluetoothServicePort   = 45679;
  static const int wifiDirectPort         = 45678;

  // ──────────────────────────── Истории ─────────────────────────────
  static const int storyTtlHours          = 24;

  // ──────────────────────────── Тайм-ауты ───────────────────────────
  static const int connectTimeoutSec      = 15;
  static const int receiveTimeoutSec      = 30;
}
