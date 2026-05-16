import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/config/app_config.dart';

class NotificationsSettings extends StatefulWidget {
  const NotificationsSettings({super.key});
  @override State<NotificationsSettings> createState() => _NotificationsSettingsState();
}

class _NotificationsSettingsState extends State<NotificationsSettings> {
  final _storage = const FlutterSecureStorage();
  final _dio = Dio(BaseOptions(baseUrl: AppConfig.apiUrl));
  Map<String, bool> _prefs = {
    'enabled': true, 'messagePreview': true, 'sound': true, 'vibration': true,
    'badge': true, 'channelNotifications': true, 'groupNotifications': true,
    'callsEnabled': true, 'storiesEnabled': true,
  };

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final t = await _storage.read(key: 'access_token');
    if (t != null) _dio.options.headers['Authorization'] = 'Bearer $t';
    try {
      final r = await _dio.get('/settings');
      final s = r.data['settings'];
      final n = (s is Map ? (s['notifications'] as Map?) : null) ?? {};
      setState(() => _prefs = {..._prefs, ...n.map((k, v) => MapEntry(k.toString(), v == true))});
    } catch (_) {}
  }

  Future<void> _save(String key, bool val) async {
    setState(() => _prefs[key] = val);
    try { await _dio.patch('/settings/notifications', data: {key: val}); } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Уведомления')),
      body: ListView(children: [
        _Section('Основные'),
        _Switch('Уведомления включены', 'Показывать все уведомления', 'enabled'),
        _Switch('Предпросмотр сообщений', 'Текст в строке уведомления', 'messagePreview'),
        _Switch('Звук', null, 'sound'),
        _Switch('Вибрация', null, 'vibration'),
        _Switch('Значок (badge)', 'Счётчик непрочитанных на иконке', 'badge'),
        const Divider(),
        _Section('Типы уведомлений'),
        _Switch('Каналы', null, 'channelNotifications'),
        _Switch('Группы', null, 'groupNotifications'),
        _Switch('Звонки', null, 'callsEnabled'),
        _Switch('Истории', null, 'storiesEnabled'),
      ]),
    );
  }

  Widget _Section(String t) => Padding(
    padding: const EdgeInsets.only(left: 16, top: 16, bottom: 4),
    child: Text(t.toUpperCase(), style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1)),
  );

  Widget _Switch(String title, String? subtitle, String key) => SwitchListTile(
    title: Text(title), subtitle: subtitle != null ? Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93))) : null,
    value: _prefs[key] ?? true, onChanged: (v) => _save(key, v), activeColor: const Color(0xFF2AABEE),
  );
}
