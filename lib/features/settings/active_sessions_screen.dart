import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/config/app_config.dart';

class ActiveSessionsScreen extends StatefulWidget {
  const ActiveSessionsScreen({super.key});
  @override State<ActiveSessionsScreen> createState() => _ActiveSessionsState();
}

class _ActiveSessionsState extends State<ActiveSessionsScreen> {
  final _storage = const FlutterSecureStorage();
  final _dio = Dio(BaseOptions(baseUrl: AppConfig.apiUrl));
  List<Map> _sessions = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final t = await _storage.read(key: 'access_token');
    if (t != null) _dio.options.headers['Authorization'] = 'Bearer $t';
    try {
      final r = await _dio.get('/auth/sessions');
      _sessions = List<Map>.from(r.data['sessions'] ?? []);
    } catch (_) {
      // Stub if API doesn't exist yet
      _sessions = [{'device': 'Android', 'current': true, 'ip': '127.0.0.1', 'createdAt': DateTime.now().toIso8601String()}];
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _terminateOther() async {
    try {
      await _dio.delete('/auth/sessions/other');
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Все другие сессии завершены'), backgroundColor: Colors.green));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Активные сессии'),
      actions: [
        if (_sessions.length > 1)
          TextButton(
            onPressed: _terminateOther,
            child: const Text('Завершить все', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
          ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _sessions.isEmpty
            ? const Center(child: Text('Нет активных сессий', style: TextStyle(color: Color(0xFF8E8E93))))
            : ListView.builder(
                itemCount: _sessions.length,
                itemBuilder: (ctx, i) {
                  final s = _sessions[i];
                  final isCurrent = s['current'] == true;
                  return ListTile(
                    leading: Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        color: isCurrent ? const Color(0xFF2AABEE) : const Color(0xFF8E8E93).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        s['device']?.toString().contains('iOS') == true ? Icons.phone_iphone : Icons.phone_android,
                        color: isCurrent ? Colors.white : const Color(0xFF8E8E93),
                      ),
                    ),
                    title: Text(
                      isCurrent ? '${s['device'] ?? 'Это устройство'} (текущее)' : (s['device']?.toString() ?? 'Устройство'),
                      style: TextStyle(fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal),
                    ),
                    subtitle: Text(s['ip']?.toString() ?? ''),
                    trailing: !isCurrent
                        ? TextButton(
                            onPressed: () async {
                              try {
                                await _dio.delete('/auth/sessions/${s['id'] ?? s['_id']}');
                                await _load();
                              } catch (_) {}
                            },
                            child: const Text('Завершить', style: TextStyle(color: Colors.red)),
                          )
                        : null,
                  );
                },
              ),
  );
}
