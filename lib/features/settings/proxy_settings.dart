import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/config/app_config.dart';

/// Настройки прокси — SOCKS5 / HTTP / MTProto (как в Telegram)
class ProxySettings extends StatefulWidget {
  const ProxySettings({super.key});

  @override
  State<ProxySettings> createState() => _ProxySettingsState();
}

class _ProxySettingsState extends State<ProxySettings> {
  final _storage = const FlutterSecureStorage();
  final _dio = Dio(BaseOptions(baseUrl: AppConfig.apiUrl));

  bool _enabled = false;
  String _type = 'socks5';
  final _hostCtrl = TextEditingController();
  final _portCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _secretCtrl = TextEditingController();
  bool _useForCalls = false;
  bool _loading = false;
  bool _testing = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = await _storage.read(key: 'access_token');
    if (token != null) _dio.options.headers['Authorization'] = 'Bearer $token';
    try {
      final r = await _dio.get('/settings/proxy');
      final p = ((r.data['proxy']) as Map?) ?? {};
      setState(() {
        _enabled = p['enabled'] == true;
        _type = p['type'] ?? 'socks5';
        _hostCtrl.text = p['host'] ?? '';
        _portCtrl.text = (p['port'] ?? 0).toString();
        _userCtrl.text = p['username'] ?? '';
        _secretCtrl.text = p['secret'] ?? '';
        _useForCalls = p['useForCalls'] == true;
      });
    } catch (_) {}
  }

  Future<void> _save() async {
    setState(() => _loading = true);
    try {
      await _dio.patch('/settings/proxy', data: {
        'enabled': _enabled,
        'type': _type,
        'host': _hostCtrl.text.trim(),
        'port': int.tryParse(_portCtrl.text.trim()) ?? 0,
        'username': _userCtrl.text.trim(),
        'password': _passCtrl.text,
        'secret': _secretCtrl.text.trim(),
        'useForCalls': _useForCalls,
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Настройки прокси сохранены'), backgroundColor: Colors.green),
      );
    } catch (_) {} finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _test() async {
    setState(() { _testing = true; _testResult = null; });
    try {
      final r = await _dio.post('/settings/proxy/test', data: {
        'host': _hostCtrl.text.trim(), 'port': int.tryParse(_portCtrl.text.trim()) ?? 0, 'type': _type,
      });
      setState(() => _testResult = r.data['reachable'] == true
          ? 'Прокси доступен ✓'
          : 'Не удалось подключиться');
    } catch (_) {
      setState(() => _testResult = 'Ошибка проверки');
    } finally {
      setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Прокси и VPN'),
        actions: [
          TextButton(
            onPressed: _loading ? null : _save,
            child: const Text('Сохранить', style: TextStyle(color: Color(0xFF2AABEE), fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [

          // Включить прокси
          SwitchListTile(
            value: _enabled,
            onChanged: (v) => setState(() => _enabled = v),
            title: const Text('Использовать прокси', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('Все соединения через прокси-сервер'),
            activeColor: const Color(0xFF2AABEE),
            contentPadding: EdgeInsets.zero,
          ),

          if (_enabled) ...[
            const SizedBox(height: 16),

            // Тип прокси
            const Text('Тип прокси', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'socks5', label: Text('SOCKS5')),
                ButtonSegment(value: 'http', label: Text('HTTP')),
                ButtonSegment(value: 'mtproto', label: Text('MTProto')),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith((states) =>
                    states.contains(WidgetState.selected) ? const Color(0xFF2AABEE) : null),
              ),
            ),
            const SizedBox(height: 20),

            // Хост и порт
            Row(children: [
              Expanded(flex: 3, child: _field('Хост / IP', _hostCtrl, TextInputType.url)),
              const SizedBox(width: 12),
              Expanded(flex: 1, child: _field('Порт', _portCtrl, TextInputType.number,
                  hint: _type == 'socks5' ? '1080' : _type == 'http' ? '8080' : '443')),
            ]),
            const SizedBox(height: 12),

            if (_type != 'mtproto') ...[
              _field('Логин (необязательно)', _userCtrl, TextInputType.text),
              const SizedBox(height: 12),
              _field('Пароль', _passCtrl, TextInputType.text, obscure: true),
            ],

            if (_type == 'mtproto') ...[
              _field('Secret', _secretCtrl, TextInputType.text),
              const SizedBox(height: 4),
              const Text(
                'MTProto secret можно получить у вашего провайдера прокси',
                style: TextStyle(fontSize: 12, color: Color(0xFF8E8E93)),
              ),
            ],

            const SizedBox(height: 16),
            SwitchListTile(
              value: _useForCalls,
              onChanged: (v) => setState(() => _useForCalls = v),
              title: const Text('Использовать для звонков'),
              activeColor: const Color(0xFF2AABEE),
              contentPadding: EdgeInsets.zero,
            ),

            const SizedBox(height: 16),

            // Тест соединения
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _testing ? null : _test,
                  icon: _testing
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.speed_outlined),
                  label: const Text('Проверить соединение'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF2AABEE),
                    side: const BorderSide(color: Color(0xFF2AABEE)),
                  ),
                ),
              ),
            ]),

            if (_testResult != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _testResult!.contains('✓')
                      ? Colors.green.withOpacity(0.1)
                      : Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_testResult!,
                    style: TextStyle(color: _testResult!.contains('✓') ? Colors.green : Colors.red)),
              ),
            ],
          ],

          const SizedBox(height: 32),

          // Информация
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF2AABEE).withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Как это работает', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                SizedBox(height: 8),
                Text(
                  '• SOCKS5 — универсальный прокси, работает с чатами и звонками\n'
                  '• HTTP — только для HTTP/HTTPS трафика\n'
                  '• MTProto — специальный протокол для обхода блокировок\n\n'
                  'Прокси шифрует ваш IP-адрес и помогает обойти ограничения',
                  style: TextStyle(fontSize: 13, height: 1.5, color: Color(0xFF8E8E93)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl, TextInputType type,
      {bool obscure = false, String? hint}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 13, fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          keyboardType: type,
          obscureText: obscure,
          decoration: InputDecoration(
            hintText: hint ?? label,
            filled: true,
            fillColor: const Color(0xFFF5F5F5),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _hostCtrl.dispose(); _portCtrl.dispose();
    _userCtrl.dispose(); _passCtrl.dispose(); _secretCtrl.dispose();
    super.dispose();
  }
}

