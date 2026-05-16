import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/config/app_config.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _storage = const FlutterSecureStorage();
  final _dio = Dio(BaseOptions(baseUrl: AppConfig.apiUrl));
  Map? _user;
  bool _loading = true;
  bool _editing = false;
  final _nameCtrl = TextEditingController();
  final _bioCtrl  = TextEditingController();

  static const _statuses = ['🟢 В сети', '🌙 Не беспокоить', '✈️ В дороге', '🤐 Молчу', '💼 На работе', '🏖 В отпуске'];
  String _status = '🟢 В сети';

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final t = await _storage.read(key: 'access_token');
    if (t != null) _dio.options.headers['Authorization'] = 'Bearer $t';
    try {
      final r = await _dio.get('/auth/me');
      final u = (r.data['user'] as Map?) ?? (r.data as Map?) ?? {};
      setState(() {
        _user = u;
        _nameCtrl.text = u['name'] ?? '';
        _bioCtrl.text  = u['bio']  ?? '';
        _loading = false;
      });
    } catch (_) { setState(() => _loading = false); }
  }

  Future<void> _save() async {
    try {
      await _dio.patch('/users/me', data: {'name': _nameCtrl.text.trim(), 'bio': _bioCtrl.text.trim()});
      setState(() => _editing = false);
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Профиль обновлён'), backgroundColor: Colors.green));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final u = _user ?? {};
    final name   = u['name']  ?? 'Пользователь';
    final login  = u['login'] ?? '';
    final email  = u['email'] ?? '';
    final bio    = u['bio']   ?? '';
    final online = u['online'] == true;
    final lastSeen = u['lastSeen'];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Мой профиль'),
        actions: [
          _editing
              ? TextButton(onPressed: _save, child: const Text('Сохранить', style: TextStyle(color: Color(0xFF2AABEE), fontWeight: FontWeight.w700)))
              : IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => setState(() => _editing = true)),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Аватар + имя + статус
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [const Color(0xFF2AABEE).withOpacity(0.1), Colors.transparent],
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                ),
              ),
              child: Column(children: [
                Stack(alignment: Alignment.bottomRight, children: [
                  CircleAvatar(radius: 52,
                    backgroundColor: const Color(0xFF2AABEE).withOpacity(0.2),
                    child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: const TextStyle(fontSize: 44, color: Color(0xFF2AABEE), fontWeight: FontWeight.w700)),
                  ),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(color: Color(0xFF2AABEE), shape: BoxShape.circle),
                    child: const Icon(Icons.camera_alt, color: Colors.white, size: 16),
                  ),
                ]),
                const SizedBox(height: 16),
                _editing
                    ? TextField(controller: _nameCtrl, textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                        decoration: const InputDecoration(hintText: 'Ваше имя', border: OutlineInputBorder()))
                    : Text(name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Container(width: 10, height: 10, margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(color: online ? Colors.green : const Color(0xFF8E8E93), shape: BoxShape.circle)),
                  Text(online ? 'В сети' : 'Был(а) недавно', style: const TextStyle(color: Color(0xFF8E8E93))),
                ]),
              ]),
            ),

            // Статус (кастомный)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                child: ListTile(
                  leading: const Icon(Icons.mood_outlined, color: Color(0xFF2AABEE)),
                  title: const Text('Статус'),
                  subtitle: Text(_status),
                  trailing: const Icon(Icons.chevron_right, color: Color(0xFF8E8E93)),
                  onTap: _pickStatus,
                ),
              ),
            ),

            const SizedBox(height: 8),

            // Информация
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                child: Column(children: [
                  _infoRow(Icons.alternate_email, 'Логин', '@$login'),
                  const Divider(height: 0, indent: 56),
                  _infoRow(Icons.mail_outline, 'Email', email),
                  const Divider(height: 0, indent: 56),
                  _editing
                      ? ListTile(
                          leading: const Icon(Icons.info_outline, color: Color(0xFF2AABEE)),
                          title: TextField(controller: _bioCtrl, decoration: const InputDecoration(hintText: 'Расскажите о себе...'), maxLines: 3),
                        )
                      : _infoRow(Icons.info_outline, 'О себе', bio.isEmpty ? 'Нет биографии' : bio),
                ]),
              ),
            ),

            const SizedBox(height: 8),

            // Конфиденциальность
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                child: Column(children: [
                  ListTile(
                    leading: const Icon(Icons.phone_outlined, color: Color(0xFF2AABEE)),
                    title: const Text('Номер телефона'),
                    subtitle: const Text('Не привязан'),
                    trailing: TextButton(onPressed: () {}, child: const Text('Добавить')),
                  ),
                  const Divider(height: 0, indent: 56),
                  ListTile(
                    leading: const Icon(Icons.qr_code, color: Color(0xFF2AABEE)),
                    title: const Text('Мой QR-код'),
                    subtitle: const Text('Поделиться профилем'),
                    trailing: const Icon(Icons.chevron_right, color: Color(0xFF8E8E93)),
                    onTap: () => _showQR(context, login),
                  ),
                ]),
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF2AABEE)),
      title: Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93))),
      subtitle: Text(value, style: const TextStyle(fontSize: 15, color: Colors.black87)),
    );
  }

  void _pickStatus() {
    showModalBottomSheet(context: context, builder: (_) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Padding(padding: EdgeInsets.all(16), child: Text('Выбрать статус', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
        ..._statuses.map((s) => ListTile(
          title: Text(s, style: const TextStyle(fontSize: 16)),
          trailing: _status == s ? const Icon(Icons.check, color: Color(0xFF2AABEE)) : null,
          onTap: () { setState(() => _status = s); Navigator.pop(context); },
        )),
      ]),
    ));
  }

  void _showQR(BuildContext ctx, String login) {
    showDialog(context: ctx, builder: (_) => AlertDialog(
      title: const Text('QR-код профиля'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 200, height: 200,
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xFF2AABEE), width: 2), borderRadius: BorderRadius.circular(12)),
          child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.qr_code, size: 100, color: Color(0xFF2AABEE)),
            Text('@$login', style: const TextStyle(fontWeight: FontWeight.w700)),
          ])),
        ),
        const SizedBox(height: 8),
        Text('nusha://user/$login', style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93))),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Закрыть'))],
    ));
  }

  @override
  void dispose() { _nameCtrl.dispose(); _bioCtrl.dispose(); super.dispose(); }
}

