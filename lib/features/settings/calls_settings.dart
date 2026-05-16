import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/config/app_config.dart';

class CallsSettings extends StatefulWidget {
  const CallsSettings({super.key});
  @override State<CallsSettings> createState() => _CallsSettingsState();
}

class _CallsSettingsState extends State<CallsSettings> {
  final _storage = const FlutterSecureStorage();
  final _dio = Dio(BaseOptions(baseUrl: AppConfig.apiUrl));

  bool _noiseCancellation = true;
  bool _useProxy           = false;
  bool _videoEnabled       = true;
  bool _mirrorCamera       = true;
  bool _lowData            = false;
  String _codec            = 'opus';
  bool _loading            = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final t = await _storage.read(key: 'access_token');
    if (t != null) _dio.options.headers['Authorization'] = 'Bearer $t';
    try {
      final r = await _dio.get('/settings');
      final c = (r.data['settings']?['calls'] as Map?) ?? {};
      setState(() {
        _noiseCancellation = c['noiseCancellation'] != false;
        _useProxy = c['useProxy'] == true;
        _videoEnabled = c['videoEnabled'] != false;
        _mirrorCamera = c['mirrorCamera'] != false;
        _lowData = c['lowData'] == true;
        _codec = (c['codec']?.toString()) ?? 'opus';
      });
    } catch (_) {}
  }

  Future<void> _save() async {
    setState(() => _loading = true);
    try {
      await _dio.patch('/settings/calls', data: {
        'noiseCancellation': _noiseCancellation,
        'useProxy': _useProxy,
        'videoEnabled': _videoEnabled,
        'mirrorCamera': _mirrorCamera,
        'lowData': _lowData,
        'codec': _codec,
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сохранено'), backgroundColor: Colors.green, duration: Duration(seconds: 2)));
    } catch (_) {} finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Звонки и видео'),
      actions: [
        TextButton(onPressed: _loading ? null : _save,
          child: const Text('Сохранить', style: TextStyle(color: Color(0xFF2AABEE), fontWeight: FontWeight.w600))),
      ],
    ),
    body: ListView(children: [
      _sec('Аудио'),
      SwitchListTile(
        value: _noiseCancellation,
        onChanged: (v) => setState(() => _noiseCancellation = v),
        title: const Text('Шумоподавление'),
        subtitle: const Text('ИИ-фильтрация фонового шума'),
        activeColor: const Color(0xFF2AABEE),
      ),
      ListTile(
        title: const Text('Аудиокодек'),
        subtitle: Text(_codec == 'opus' ? 'Opus (рекомендуется)' : _codec.toUpperCase()),
        trailing: DropdownButton<String>(
          value: _codec, underline: const SizedBox(),
          items: const [
            DropdownMenuItem(value: 'opus', child: Text('Opus')),
            DropdownMenuItem(value: 'pcm', child: Text('PCM')),
            DropdownMenuItem(value: 'g722', child: Text('G.722')),
          ],
          onChanged: (v) => setState(() => _codec = v ?? 'opus'),
        ),
      ),
      const Divider(),
      _sec('Видео'),
      SwitchListTile(
        value: _videoEnabled,
        onChanged: (v) => setState(() => _videoEnabled = v),
        title: const Text('Видеозвонки'),
        subtitle: const Text('Включить исходящее видео'),
        activeColor: const Color(0xFF2AABEE),
      ),
      SwitchListTile(
        value: _mirrorCamera,
        onChanged: (v) => setState(() => _mirrorCamera = v),
        title: const Text('Зеркальная камера'),
        subtitle: const Text('Отразить изображение фронтальной камеры'),
        activeColor: const Color(0xFF2AABEE),
      ),
      const Divider(),
      _sec('Данные'),
      SwitchListTile(
        value: _lowData,
        onChanged: (v) => setState(() => _lowData = v),
        title: const Text('Экономия трафика'),
        subtitle: const Text('Снижает качество для экономии данных'),
        activeColor: const Color(0xFF2AABEE),
      ),
      SwitchListTile(
        value: _useProxy,
        onChanged: (v) => setState(() => _useProxy = v),
        title: const Text('Звонки через прокси'),
        subtitle: const Text('Направить голос через настроенный прокси'),
        activeColor: const Color(0xFF2AABEE),
      ),
      const SizedBox(height: 32),
    ]),
  );

  Widget _sec(String t) => Padding(
    padding: const EdgeInsets.only(left: 16, top: 16, bottom: 4),
    child: Text(t.toUpperCase(),
      style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1)));
}
