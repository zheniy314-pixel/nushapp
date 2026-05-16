import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/config/app_config.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});
  @override State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> with SingleTickerProviderStateMixin {
  final _storage = const FlutterSecureStorage();
  late final Dio _dio;
  late final TabController _tabs;

  List<dynamic> _users    = [];
  List<dynamic> _chats    = [];
  Map<String, dynamic> _stats = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _dio = Dio(BaseOptions(baseUrl: AppConfig.apiUrl));
    _loadAll();
  }

  Future<void> _loadAll() async {
    final t = await _storage.read(key: 'access_token');
    if (t != null) _dio.options.headers['Authorization'] = 'Bearer $t';
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _dio.get('/admin/users'),
        _dio.get('/admin/stats').catchError((_) => Response(requestOptions: RequestOptions(), data: {'stats': {}})),
        _dio.get('/chats').catchError((_) => Response(requestOptions: RequestOptions(), data: {'chats': []})),
      ]);
      setState(() {
        _users = List<dynamic>.from(results[0].data['users'] ?? results[0].data ?? []);
        _stats = Map<String, dynamic>.from(results[1].data['stats'] ?? results[1].data ?? {});
        _chats = List<dynamic>.from(results[2].data['chats'] ?? []);
      });
    } catch (e) {
      _showError('Ошибка загрузки: $e');
    } finally { setState(() => _loading = false); }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1D2E),
        title: Row(children: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: Colors.red.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
            child: const Text('ADMIN', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 2))),
          const SizedBox(width: 12),
          const Text('Нуша — Панель', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        ]),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, color: Colors.white70), onPressed: _loadAll),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: const Color(0xFF2AABEE),
          labelColor: const Color(0xFF2AABEE),
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(icon: Icon(Icons.bar_chart, size: 18), text: 'Статистика'),
            Tab(icon: Icon(Icons.people, size: 18), text: 'Пользователи'),
            Tab(icon: Icon(Icons.chat_bubble_outline, size: 18), text: 'Чаты'),
            Tab(icon: Icon(Icons.settings, size: 18), text: 'Система'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF2AABEE)))
          : TabBarView(
              controller: _tabs,
              children: [
                _statsTab(),
                _usersTab(),
                _chatsTab(),
                _systemTab(),
              ],
            ),
    );
  }

  // ─────────────── СТАТИСТИКА ───────────────
  Widget _statsTab() {
    final totalUsers  = _users.length;
    final onlineUsers = _users.where((u) => u['online'] == true).length;
    final totalChats  = _chats.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        const SizedBox(height: 8),
        Row(children: [
          _statCard('Пользователей', totalUsers.toString(), Icons.people, Colors.blue),
          const SizedBox(width: 12),
          _statCard('Онлайн сейчас', onlineUsers.toString(), Icons.circle, Colors.green),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          _statCard('Чатов', totalChats.toString(), Icons.chat_bubble, Colors.purple),
          const SizedBox(width: 12),
          _statCard('Сообщений', (_stats['totalMessages'] ?? '—').toString(), Icons.message, Colors.orange),
        ]),
        const SizedBox(height: 20),
        _adminCard('Активность за 24ч', Icons.timeline, [
          _adminRow('Новых пользователей', '${_stats['newUsers24h'] ?? 0}'),
          _adminRow('Сообщений отправлено', '${_stats['messages24h'] ?? 0}'),
          _adminRow('Звонков совершено',    '${_stats['calls24h'] ?? 0}'),
          _adminRow('Конференций',           '${_stats['conferences24h'] ?? 0}'),
        ]),
        const SizedBox(height: 12),
        _adminCard('Сервер', Icons.dns, [
          _adminRow('IP', AppConfig.baseUrl),
          _adminRow('Версия API', 'v1'),
          _adminRow('WebSocket', 'Подключён'),
          _adminRow('Статус БД', 'MongoDB Online'),
        ]),
        const SizedBox(height: 12),
        _adminCard('Онлайн пользователи', Icons.sensors, [
          ..._users.where((u) => u['online'] == true).map((u) =>
            _adminRow(u['name'] ?? u['login'] ?? '?', '@${u['login'] ?? ''}')),
        ]),
      ]),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Expanded(child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 8),
        Text(value, style: TextStyle(color: color, fontSize: 28, fontWeight: FontWeight.w800)),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
      ]),
    ));
  }

  Widget _adminCard(String title, IconData icon, List<Widget> rows) {
    return Container(
      decoration: BoxDecoration(color: const Color(0xFF1A1D2E), borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.all(16), child: Row(children: [
          Icon(icon, color: const Color(0xFF2AABEE), size: 20),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
        ])),
        const Divider(color: Colors.white12, height: 0),
        ...rows,
      ]),
    );
  }

  Widget _adminRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        Expanded(child: Text(label, style: const TextStyle(color: Colors.white70))),
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  // ─────────────── ПОЛЬЗОВАТЕЛИ ───────────────
  Widget _usersTab() {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _users.length,
      itemBuilder: (_, i) {
        final u = _users[i];
        final isOnline = u['online'] == true;
        final isAdmin  = u['role'] == 'admin' || u['isAdmin'] == true;
        final name  = u['name']  ?? u['login'] ?? '?';
        final email = u['email'] ?? '—';
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(color: const Color(0xFF1A1D2E), borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: Stack(children: [
              CircleAvatar(
                backgroundColor: isAdmin ? Colors.red.withOpacity(0.3) : const Color(0xFF2AABEE).withOpacity(0.2),
                child: Text(name[0].toUpperCase(),
                  style: TextStyle(color: isAdmin ? Colors.red : const Color(0xFF2AABEE), fontWeight: FontWeight.w700)),
              ),
              if (isOnline) Positioned(right: 0, bottom: 0,
                child: Container(width: 12, height: 12,
                  decoration: BoxDecoration(color: Colors.green, shape: BoxShape.circle, border: Border.all(color: Colors.black, width: 2)))),
            ]),
            title: Row(children: [
              Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              if (isAdmin) ...[const SizedBox(width: 6),
                Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: Colors.red.withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
                  child: const Text('ADMIN', style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.w900)))],
            ]),
            subtitle: Text(email, style: const TextStyle(color: Colors.white54, fontSize: 12)),
            trailing: PopupMenuButton<String>(
              color: const Color(0xFF1A1D2E),
              icon: const Icon(Icons.more_vert, color: Colors.white54),
              onSelected: (action) => _userAction(action, u),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'ban', child: Text('Заблокировать', style: TextStyle(color: Colors.red))),
                const PopupMenuItem(value: 'reset', child: Text('Сбросить пароль', style: TextStyle(color: Colors.white))),
                const PopupMenuItem(value: 'promote', child: Text('Сделать модератором', style: TextStyle(color: Colors.blue))),
                const PopupMenuItem(value: 'delete', child: Text('Удалить аккаунт', style: TextStyle(color: Colors.deepOrange))),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _userAction(String action, dynamic user) async {
    final id   = user['_id'];
    final name = user['name'] ?? user['login'];
    String msg = '';
    try {
      switch (action) {
        case 'ban':    await _dio.patch('/admin/users/$id/ban'); msg = '$name заблокирован'; break;
        case 'reset':  msg = 'Ссылка для сброса пароля отправлена на email'; break;
        case 'promote': await _dio.patch('/admin/users/$id/role', data: {'role': 'moderator'}); msg = '$name стал модератором'; break;
        case 'delete': await _dio.delete('/admin/users/$id'); msg = '$name удалён'; await _loadAll(); break;
      }
    } catch (e) { msg = 'Ошибка: $e'; }
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg),
        backgroundColor: action == 'delete' || action == 'ban' ? Colors.red : Colors.green));
  }

  // ─────────────── ЧАТЫ ───────────────
  Widget _chatsTab() {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _chats.length,
      itemBuilder: (_, i) {
        final c = _chats[i];
        final isGroup = c['type'] == 'group';
        final name = isGroup ? (c['title'] ?? 'Группа') : 'Личный чат';
        final memberCount = (c['members'] as List?)?.length ?? 0;
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(color: const Color(0xFF1A1D2E), borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isGroup ? Colors.deepPurple.withOpacity(0.3) : const Color(0xFF2AABEE).withOpacity(0.2),
              child: Icon(isGroup ? Icons.group : Icons.person, color: isGroup ? Colors.deepPurple : const Color(0xFF2AABEE), size: 20),
            ),
            title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            subtitle: Text('$memberCount участников', style: const TextStyle(color: Colors.white54, fontSize: 12)),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: () => _confirmDeleteChat(c['_id'], name),
            ),
          ),
        );
      },
    );
  }

  void _confirmDeleteChat(String chatId, String name) {
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF1A1D2E),
      title: Text('Удалить чат "$name"?', style: const TextStyle(color: Colors.white)),
      content: const Text('Все сообщения будут удалены.', style: TextStyle(color: Colors.white54)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        TextButton(
          onPressed: () async {
            Navigator.pop(context);
            try { await _dio.delete('/chats/$chatId/leave'); await _loadAll(); } catch (_) {}
          },
          child: const Text('Удалить', style: TextStyle(color: Colors.red)),
        ),
      ],
    ));
  }

  // ─────────────── СИСТЕМА ───────────────
  Widget _systemTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        _adminCard('Уведомления', Icons.notifications_active, [
          _actionRow('Отправить анонс всем', Icons.campaign, Colors.orange, () => _sendAnnouncement()),
        ]),
        const SizedBox(height: 12),
        _adminCard('Управление системой', Icons.settings_applications, [
          _actionRow('Принудительный выход всех', Icons.logout, Colors.red, () {}),
          _actionRow('Очистить кеш сервера', Icons.cleaning_services, Colors.blue, () {}),
          _actionRow('Перезапустить новостной парсер', Icons.rss_feed, Colors.green, () {}),
        ]),
        const SizedBox(height: 12),
        _adminCard('Логи', Icons.terminal, [
          _actionRow('PM2 логи', Icons.article, Colors.white54, () {}),
          _actionRow('Nginx логи', Icons.dns, Colors.white54, () {}),
          _actionRow('MongoDB логи', Icons.storage, Colors.white54, () {}),
        ]),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.red.withOpacity(0.3)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('⚠️ ОПАСНАЯ ЗОНА', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w900, letterSpacing: 2)),
            const SizedBox(height: 12),
            OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)),
              onPressed: () {},
              child: const Text('Полная очистка базы данных'),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _actionRow(String label, IconData icon, Color color, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label, style: const TextStyle(color: Colors.white70)),
      trailing: const Icon(Icons.chevron_right, color: Colors.white24),
      onTap: onTap,
    );
  }

  void _sendAnnouncement() {
    final ctrl = TextEditingController();
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF1A1D2E),
      title: const Text('Анонс всем пользователям', style: TextStyle(color: Colors.white)),
      content: TextField(
        controller: ctrl, maxLines: 3,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Текст объявления...', hintStyle: const TextStyle(color: Colors.white38),
          filled: true, fillColor: Colors.white10,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
          onPressed: () async {
            Navigator.pop(context);
            try {
              await _dio.post('/admin/broadcast', data: {'message': ctrl.text.trim()});
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Анонс отправлен!'), backgroundColor: Colors.green));
            } catch (_) {}
          },
          child: const Text('Отправить'),
        ),
      ],
    ));
  }

  @override
  void dispose() { _tabs.dispose(); super.dispose(); }
}
