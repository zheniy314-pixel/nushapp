import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/config/app_config.dart';

class DisappearSettings extends StatefulWidget {
  const DisappearSettings({super.key});
  @override State<DisappearSettings> createState() => _DisappearSettingsState();
}

class _DisappearSettingsState extends State<DisappearSettings> {
  final _storage = const FlutterSecureStorage();
  final _dio = Dio(BaseOptions(baseUrl: AppConfig.apiUrl));
  int _seconds = 0;
  bool _loading = false;

  static const _opts = [
    {'label': 'Выключено', 'secs': 0},
    {'label': '5 секунд', 'secs': 5},
    {'label': '1 минута', 'secs': 60},
    {'label': '1 час', 'secs': 3600},
    {'label': '1 день', 'secs': 86400},
    {'label': '1 неделя', 'secs': 604800},
  ];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final t = await _storage.read(key: 'access_token');
    if (t != null) _dio.options.headers['Authorization'] = 'Bearer $t';
    try {
      final r = await _dio.get('/auth/me');
      final u = (r.data['user'] as Map?) ?? {};
      setState(() => _seconds = (u['defaultDisappearTimer'] as num?)?.toInt() ?? 0);
    } catch (_) {}
  }

  Future<void> _set(int secs) async {
    setState(() { _seconds = secs; _loading = true; });
    try {
      await _dio.patch('/settings/disappear', data: {'seconds': secs});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(secs == 0 ? 'Автоудаление выключено' : 'Сообщения исчезнут через ${_label(secs)}'),
          backgroundColor: Colors.green, duration: const Duration(seconds: 2)));
    } catch (_) {} finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _label(int s) {
    for (final o in _opts) if (o['secs'] == s) return o['label'] as String;
    return '$s сек';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Исчезающие сообщения')),
    body: Column(children: [
      Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF2AABEE).withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          const Icon(Icons.timer_outlined, color: Color(0xFF2AABEE), size: 28),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Автоудаление', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 4),
            Text(
              _seconds == 0
                  ? 'Выключено. Сообщения хранятся бессрочно.'
                  : 'Новые сообщения будут удаляться через ${_label(_seconds)}.',
              style: const TextStyle(fontSize: 13, color: Color(0xFF8E8E93)),
            ),
          ])),
        ]),
      ),
      Expanded(
        child: ListView.builder(
          itemCount: _opts.length,
          itemBuilder: (ctx, i) {
            final opt = _opts[i];
            final secs = opt['secs'] as int;
            final label = opt['label'] as String;
            return ListTile(
              leading: Icon(
                secs == 0 ? Icons.timer_off_outlined : Icons.timer_outlined,
                color: secs == _seconds ? const Color(0xFF2AABEE) : const Color(0xFF8E8E93),
              ),
              title: Text(label, style: TextStyle(
                fontWeight: secs == _seconds ? FontWeight.w600 : FontWeight.normal,
                color: secs == _seconds ? const Color(0xFF2AABEE) : null,
              )),
              trailing: _seconds == secs
                  ? const Icon(Icons.check_circle, color: Color(0xFF2AABEE))
                  : null,
              onTap: _loading ? null : () => _set(secs),
            );
          },
        ),
      ),
    ]),
  );
}
