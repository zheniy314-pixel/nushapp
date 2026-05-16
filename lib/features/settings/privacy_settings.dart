import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/config/app_config.dart';

class PrivacySettings extends StatefulWidget {
  const PrivacySettings({super.key});
  @override State<PrivacySettings> createState() => _PrivacySettingsState();
}

class _PrivacySettingsState extends State<PrivacySettings> {
  final _storage = const FlutterSecureStorage();
  final _dio = Dio(BaseOptions(baseUrl: AppConfig.apiUrl));
  Map<String, dynamic> _prefs = {
    'lastSeenVisibility': 'everyone', 'profilePhotoVisibility': 'everyone',
    'callsFrom': 'everyone', 'forwardedMessages': 'everyone',
    'groupAddPermission': 'everyone', 'readReceipts': true,
    'typingStatus': true, 'onlineStatus': true, 'linkPreview': true,
  };

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final t = await _storage.read(key: 'access_token');
    if (t != null) _dio.options.headers['Authorization'] = 'Bearer $t';
    try {
      final r = await _dio.get('/settings');
      setState(() => _prefs = Map<String, dynamic>.from(r.data['settings']['privacy'] as Map));
    } catch (_) {}
  }

  Future<void> _save(String k, dynamic v) async {
    setState(() => _prefs[k] = v);
    try { await _dio.patch('/settings/privacy', data: {k: v}); } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    const opts = ['everyone', 'contacts', 'nobody'];
    const labels = ['Все', 'Контакты', 'Никто'];

    Widget dropRow(String title, String key) => ListTile(
      title: Text(title),
      trailing: DropdownButton<String>(
        value: _prefs[key] as String? ?? 'everyone',
        underline: const SizedBox(),
        items: List.generate(opts.length, (i) => DropdownMenuItem(value: opts[i], child: Text(labels[i]))),
        onChanged: (v) => v != null ? _save(key, v) : null,
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Конфиденциальность')),
      body: ListView(children: [
        _Sec('Кто видит'),
        dropRow('Время посещения', 'lastSeenVisibility'),
        dropRow('Фото профиля', 'profilePhotoVisibility'),
        dropRow('Звонки от', 'callsFrom'),
        dropRow('Пересланные сообщения', 'forwardedMessages'),
        dropRow('Кто может добавить в группу', 'groupAddPermission'),
        const Divider(),
        _Sec('Дополнительно'),
        SwitchListTile(title: const Text('Голубые галочки (прочитано)'),
            value: _prefs['readReceipts'] == true, onChanged: (v) => _save('readReceipts', v), activeColor: const Color(0xFF2AABEE)),
        SwitchListTile(title: const Text('Статус "печатает..."'),
            value: _prefs['typingStatus'] == true, onChanged: (v) => _save('typingStatus', v), activeColor: const Color(0xFF2AABEE)),
        SwitchListTile(title: const Text('Статус "в сети"'),
            value: _prefs['onlineStatus'] == true, onChanged: (v) => _save('onlineStatus', v), activeColor: const Color(0xFF2AABEE)),
        SwitchListTile(title: const Text('Предпросмотр ссылок'),
            subtitle: const Text('Показывать превью URL в сообщениях', style: TextStyle(fontSize: 12)),
            value: _prefs['linkPreview'] == true, onChanged: (v) => _save('linkPreview', v), activeColor: const Color(0xFF2AABEE)),
      ]),
    );
  }

  Widget _Sec(String t) => Padding(
    padding: const EdgeInsets.only(left: 16, top: 16, bottom: 4),
    child: Text(t.toUpperCase(), style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1)),
  );
}
