import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../calculator/calculator_screen.dart';
import 'profile_screen.dart';
import '../admin/admin_screen.dart';
import 'notifications_settings.dart';
import 'privacy_settings.dart';
import 'proxy_settings.dart';
import 'appearance_settings.dart';
import 'storage_settings.dart';
import 'security_settings.dart';
import 'mail_settings.dart';
import 'offline_settings.dart';
import 'language_settings.dart';
import 'calls_settings.dart';
import 'disappear_settings.dart';
import 'active_sessions_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        children: [

          // ─── Профиль ────────────────────────────────────────────
          _ProfileTile(onTap: () => _push(context, const ProfileScreen())),
          const Divider(height: 0),

          // ─── Аккаунт ─────────────────────────────────────────────
          _SectionHeader('Аккаунт'),
          _Tile(Icons.notifications_outlined, const Color(0xFF2AABEE),
            'Уведомления и звуки', () => _push(context, const NotificationsSettings())),
          _Tile(Icons.lock_outline, Colors.deepPurple,
            'Конфиденциальность и безопасность', () => _push(context, const PrivacySettings())),
          _Tile(Icons.storage_outlined, Colors.orange,
            'Данные и хранилище', () => _push(context, const StorageSettings())),
          _Tile(Icons.palette_outlined, Colors.pink,
            'Оформление', () => _push(context, const AppearanceSettings())),
          _Tile(Icons.language_outlined, Colors.teal,
            'Язык', () => _push(context, const LanguageSettings())),

          const Divider(height: 0),

          // ─── Связь и сеть ─────────────────────────────────────────
          _SectionHeader('Связь и сеть'),
          _Tile(Icons.vpn_lock_outlined, Colors.green,
            'Прокси и VPN (SOCKS5 / HTTP)', () => _push(context, const ProxySettings()),
            subtitle: 'SOCKS5, HTTP, MTProto'),
          _Tile(Icons.bluetooth_outlined, Colors.blue,
            'Офлайн-доставка', () => _push(context, const OfflineSettings()),
            subtitle: 'Bluetooth · WiFi Direct · SMS'),
          _Tile(Icons.call_outlined, const Color(0xFF2AABEE),
            'Звонки и видео', () => _push(context, const CallsSettings())),

          const Divider(height: 0),

          // ─── Безопасность ─────────────────────────────────────────
          _SectionHeader('Безопасность'),
          _Tile(Icons.shield_outlined, Colors.red,
            'Пароль и биометрия', () => _push(context, const SecuritySettings())),
          _Tile(Icons.pin_outlined, Colors.orange,
            'Секретный PIN (калькулятор)', () => _showPinDialog(context)),
          _Tile(Icons.warning_amber_outlined, Colors.deepOrange,
            'Panic PIN', () => _showPanicDialog(context)),
          _Tile(Icons.timer_outlined, Colors.amber,
            'Исчезающие сообщения', () => _push(context, const DisappearSettings())),

          const Divider(height: 0),

          // ─── Почта ────────────────────────────────────────────────
          _SectionHeader('Почта'),
          _Tile(Icons.mail_outlined, const Color(0xFF2AABEE),
            'Настройки почты', () => _push(context, const MailSettings()),
            subtitle: 'IMAP · SMTP · подпись · внешний ящик'),

          const Divider(height: 0),

          // ─── Устройства ───────────────────────────────────────────
          _SectionHeader('Устройства'),
          _Tile(Icons.devices_outlined, Colors.blueGrey,
            'Активные сессии', () => _push(context, const ActiveSessionsScreen())),
          _Tile(Icons.qr_code_outlined, Colors.indigo,
            'Привязать устройство', () => _showQrLinkDevice(context)),

          const Divider(height: 0),

          // ─── О программе ──────────────────────────────────────────
          _SectionHeader('О программе'),
          _Tile(Icons.info_outline, Colors.grey,
            'Версия 1.1.0 (build 2)', () => _showAbout(context)),
          _Tile(Icons.bug_report_outlined, Colors.grey,
            'Сообщить о проблеме', () => _showReport(context)),
          _Tile(Icons.admin_panel_settings, Colors.red.shade900,
            'Панель администратора', () => _push(context, const AdminScreen()),
            subtitle: 'Управление пользователями и системой'),
          _Tile(Icons.logout, Colors.red,
            'Выйти из аккаунта', () => _logout(context)),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  void _push(BuildContext ctx, Widget screen) {
    Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => screen));
  }

  void _showQrLinkDevice(BuildContext context) {
    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text('Привязать устройство'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 180, height: 180,
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xFF2AABEE), width: 2), borderRadius: BorderRadius.circular(12)),
          child: const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.qr_code, size: 100, color: Color(0xFF2AABEE)),
            SizedBox(height: 8),
            Text('QR для входа', style: TextStyle(fontSize: 12, color: Color(0xFF8E8E93))),
          ])),
        ),
        const SizedBox(height: 12),
        const Text('Откройте Нуша на другом устройстве и отсканируйте QR-код', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Color(0xFF8E8E93))),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Закрыть'))],
    ));
  }

  void _showAbout(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'Нуша',
      applicationVersion: '1.1.0 (build 2)',
      applicationLegalese: '© 2026 nushik.info',
      children: const [
        SizedBox(height: 8),
        Text('Защищённый мессенджер с маскировкой под калькулятор.\nE2E-шифрование · WebRTC · Офлайн-доставка'),
      ],
    );
  }

  void _showReport(BuildContext context) {
    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text('Сообщить о проблеме'),
      content: const Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Опишите проблему и отправьте на:'),
        SizedBox(height: 8),
        SelectableText('support@nushik.info', style: TextStyle(color: Color(0xFF2AABEE), fontWeight: FontWeight.w600)),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Понятно'))],
    ));
  }

  void _showPinDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Секретный PIN'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Этот PIN открывает мессенджер из калькулятора.'),
            SizedBox(height: 8),
            Text('Введите новый PIN (4–8 цифр):'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('Изменить', style: TextStyle(color: Color(0xFF2AABEE)))),
        ],
      ),
    );
  }

  void _showPanicDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Panic PIN'),
        content: const Text(
          'Panic PIN мгновенно удаляет ВСЕ данные мессенджера.\n\n'
          'Введите на калькуляторе — через 1 секунду всё исчезнет.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('Изменить', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  Future<void> _logout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Выйти?'),
        content: const Text('Данные останутся на устройстве.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Выйти', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      const FlutterSecureStorage().deleteAll();
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const CalculatorScreen()), (_) => false);
    }
  }
}

class _ProfileTile extends StatelessWidget {
  final VoidCallback? onTap;
  const _ProfileTile({this.onTap});
  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: const CircleAvatar(
        radius: 28,
        backgroundColor: Color(0xFF2AABEE),
        child: Icon(Icons.person, color: Colors.white, size: 30),
      ),
      title: const Text('Мой профиль', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17)),
      subtitle: const Text('Имя, фото, статус, username'),
      trailing: const Icon(Icons.chevron_right, color: Color(0xFF8E8E93)),
      onTap: onTap,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, top: 20, bottom: 6, right: 16),
      child: Text(title.toUpperCase(),
          style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1)),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final VoidCallback onTap;
  final String? subtitle;
  const _Tile(this.icon, this.color, this.title, this.onTap, {this.subtitle});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 34, height: 34,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
      title: Text(title, style: const TextStyle(fontSize: 15)),
      subtitle: subtitle != null ? Text(subtitle!, style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93))) : null,
      trailing: const Icon(Icons.chevron_right, size: 18, color: Color(0xFF8E8E93)),
      onTap: onTap,
    );
  }
}
