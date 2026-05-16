import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/config/app_config.dart';
import '../../core/services/socket_service.dart';
import 'chat_screen.dart';
import 'create_group_screen.dart';
import '../conferences/conference_screen.dart';

class ChatsListScreen extends StatefulWidget {
  const ChatsListScreen({super.key});
  @override State<ChatsListScreen> createState() => _ChatsListScreenState();
}

class _ChatsListScreenState extends State<ChatsListScreen> with WidgetsBindingObserver {
  final _storage = const FlutterSecureStorage();
  final _socket  = SocketService();
  late final Dio _dio;
  List<dynamic> _chats = [];
  bool _loading = false;
  String? _myUserId;
  String? _myName;

  StreamSubscription? _subMsg;
  StreamSubscription? _subPresence;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _dio = Dio(BaseOptions(baseUrl: AppConfig.apiUrl, connectTimeout: const Duration(seconds: 10)));
    _load();
    _subscribeSocket();
  }

  void _subscribeSocket() {
    // Real-time: new message → update lastMessage preview
    _subMsg = _socket.onMessageNew.listen((data) {
      final chatId  = data['chatId'] as String? ?? '';
      final msg     = data['message'] as Map<String, dynamic>? ?? {};
      final sender  = data['senderName'] as String? ?? '';
      if (!mounted) return;
      setState(() {
        final idx = _chats.indexWhere((c) => c['_id'] == chatId);
        if (idx >= 0) {
          _chats[idx]['lastMessage'] = {
            'text': msg['text'] ?? '',
            'type': msg['type'] ?? 'text',
            'at':   msg['createdAt'] ?? DateTime.now().toIso8601String(),
            'senderName': sender,
          };
          // Move this chat to top
          final chat = _chats.removeAt(idx);
          _chats.insert(0, chat);
        } else {
          _load(); // unknown chat — refresh
        }
      });
    });

    // Real-time: presence → update online dot in chat list
    _subPresence = _socket.onPresenceUpdate.listen((data) {
      final userId = data['userId'] as String? ?? '';
      final online = data['online'] == true;
      final lastSeen = data['lastSeen'];
      if (!mounted) return;
      setState(() {
        for (final chat in _chats) {
          final members = List<dynamic>.from(chat['members'] ?? []);
          for (final m in members) {
            if (m is Map && (m['_id'] ?? m['id'])?.toString() == userId) {
              m['online'] = online;
              if (lastSeen != null) m['lastSeen'] = lastSeen;
              // Refresh resolved name cache
              if (chat['type'] == 'direct') {
                chat['_resolvedOnline'] = online;
              }
            }
          }
        }
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subMsg?.cancel();
    _subPresence?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final token = await _storage.read(key: 'access_token');
      _myUserId   = await _storage.read(key: 'user_id');
      if (token != null) _dio.options.headers['Authorization'] = 'Bearer $token';
      final r = await _dio.get('/chats');
      final chats = List<dynamic>.from(r.data['chats'] ?? []);
      // Resolve real names for direct chats
      for (final chat in chats) {
        if (chat['type'] == 'direct') {
          final members = List<dynamic>.from(chat['members'] ?? []);
          final other = members.firstWhere(
            (m) {
              final id = m is Map ? (m['_id'] ?? m['id']) : m.toString();
              return id != _myUserId;
            },
            orElse: () => null,
          );
          if (other != null && other is Map) {
            chat['_resolvedName']   = other['name']  ?? other['login'] ?? 'Пользователь';
            chat['_resolvedOnline'] = other['online'] ?? false;
            chat['_resolvedLogin']  = other['login']  ?? '';
            // Use MongoDB _id for socket routing (NOT login)
            chat['_resolvedId']     = other['_id']?.toString() ?? other['id']?.toString() ?? '';
          }
        }
      }
      setState(() => _chats = chats);
    } catch (_) {} finally { setState(() => _loading = false); }
  }

  String _chatName(dynamic chat) {
    if (chat['type'] == 'direct') return chat['_resolvedName'] ?? 'Личный чат';
    return chat['title'] ?? 'Группа';
  }

  bool _chatOnline(dynamic chat) {
    if (chat['type'] == 'direct') return chat['_resolvedOnline'] == true;
    return false;
  }

  String _lastMsg(dynamic chat) {
    final lm = chat['lastMessage'];
    if (lm == null) return 'Нет сообщений';
    final t = lm['type'] ?? 'text';
    if (t == 'image') return '📷 Фото';
    if (t == 'voice') return '🎙 Голосовое';
    if (t == 'call')  return '📞 Звонок';
    return lm['text'] ?? '';
  }

  String _time(dynamic chat) {
    final lm = chat['lastMessage'];
    if (lm == null) return '';
    final d = DateTime.tryParse(lm['at'] ?? '');
    if (d == null) return '';
    final now = DateTime.now();
    if (now.difference(d).inDays == 0) {
      return '${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';
    }
    return '${d.day}.${d.month.toString().padLeft(2,'0')}';
  }

  int _unread(dynamic chat) => (chat['unreadCount'] as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Нуша', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(icon: const Icon(Icons.search), onPressed: () => _showSearch(context)),
          IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => _showNewChat(context)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _chats.isEmpty
              ? _emptyState()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    itemCount: _chats.length,
                    separatorBuilder: (_, __) => const Divider(height: 0, indent: 72),
                    itemBuilder: (_, i) => _chatTile(_chats[i]),
                  ),
                ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF2AABEE),
        child: const Icon(Icons.edit, color: Colors.white),
        onPressed: () => _showNewChat(context),
      ),
    );
  }

  Widget _chatTile(dynamic chat) {
    final name     = _chatName(chat);
    final lastMsg  = _lastMsg(chat);
    final time     = _time(chat);
    final isGroup  = chat['type'] == 'group';
    final isOnline = _chatOnline(chat);
    final unread   = _unread(chat);
    final initials = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return ListTile(
      leading: Stack(children: [
        CircleAvatar(
          backgroundColor: isGroup
              ? Colors.deepPurple.withOpacity(0.2)
              : const Color(0xFF2AABEE).withOpacity(0.2),
          child: isGroup
              ? Icon(Icons.group, color: Colors.deepPurple, size: 22)
              : Text(initials, style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF2AABEE))),
        ),
        if (isOnline)
          Positioned(right: 0, bottom: 0,
            child: Container(width: 12, height: 12,
              decoration: BoxDecoration(color: Colors.green, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)))),
      ]),
      title: Row(children: [
        Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis)),
        Text(time, style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93))),
      ]),
      subtitle: Row(children: [
        Expanded(child: Text(lastMsg, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 13))),
        if (unread > 0)
          Container(
            margin: const EdgeInsets.only(left: 4),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: const Color(0xFF2AABEE), borderRadius: BorderRadius.circular(10)),
            child: Text('$unread', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
      ]),
      onTap: () {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(
          chatId: chat['_id'] as String,
          chatName: name,
          isOnline: isOnline,
          otherUserId: chat['_resolvedId'] ?? chat['_resolvedLogin'],
        ))).then((_) => _load());
      },
      onLongPress: () => _showChatMenu(context, chat),
    );
  }

  void _showChatMenu(BuildContext ctx, dynamic chat) {
    showModalBottomSheet(context: ctx, builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(leading: const Icon(Icons.delete, color: Colors.red), title: const Text('Удалить чат', style: TextStyle(color: Colors.red)),
        onTap: () { Navigator.pop(ctx); _deleteChat(chat['_id']); }),
    ])));
  }

  Future<void> _deleteChat(String chatId) async {
    try { await _dio.delete('/chats/$chatId/leave'); await _load(); } catch (_) {}
  }

  void _showSearch(BuildContext ctx) {
    showSearch(context: ctx, delegate: _UserSearchDelegate(_dio, _myUserId, _load));
  }

  void _showNewChat(BuildContext ctx) {
    showModalBottomSheet(
      context: ctx, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Padding(padding: EdgeInsets.all(16), child: Text('Новый чат', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
        _menuItem(Icons.person_add, const Color(0xFF2AABEE), 'Новый личный чат', 'Найти пользователя',
          () { Navigator.pop(ctx); _showSearch(ctx); }),
        _menuItem(Icons.group_add, Colors.deepPurple, 'Создать группу', 'Несколько участников',
          () { Navigator.pop(ctx); Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => const CreateGroupScreen())).then((_) => _load()); }),
        _menuItem(Icons.videocam, Colors.green, 'Видеоконференция', 'Создать или войти по коду',
          () { Navigator.pop(ctx); _showConferenceDialog(ctx); }),
      ])),
    );
  }

  Widget _menuItem(IconData icon, Color color, String title, String subtitle, VoidCallback onTap) {
    return ListTile(
      leading: Container(width: 44, height: 44, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(22)),
          child: Icon(icon, color: Colors.white)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle),
      onTap: onTap,
    );
  }

  void _showConferenceDialog(BuildContext ctx) {
    final codeCtrl = TextEditingController();
    showDialog(context: ctx, builder: (_) => AlertDialog(
      title: const Text('Видеоконференция'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        ElevatedButton.icon(
          icon: const Icon(Icons.add_circle_outline),
          label: const Text('Создать новую'),
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2AABEE), minimumSize: const Size(double.infinity, 44)),
          onPressed: () async {
            Navigator.pop(ctx);
            try {
              final r = await _dio.post('/conferences/create', data: {'title': 'Конференция', 'platform': 'mobile'});
              final code = r.data['roomCode'];
              if (ctx.mounted) _showConferenceCode(ctx, code);
            } catch (_) {}
          },
        ),
        const SizedBox(height: 12),
        TextField(controller: codeCtrl, decoration: const InputDecoration(hintText: 'Код комнаты (напр. ABCD1234)', prefixIcon: Icon(Icons.meeting_room))),
        const SizedBox(height: 8),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.green, minimumSize: const Size(double.infinity, 44)),
          onPressed: () { Navigator.pop(ctx); _joinConf(ctx, codeCtrl.text.trim()); },
          child: const Text('Войти по коду'),
        ),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена'))],
    ));
  }

  void _showConferenceCode(BuildContext ctx, String code) {
    showDialog(context: ctx, builder: (dialogCtx) => AlertDialog(
      title: const Text('Конференция создана!'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Код для участников:'),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: const Color(0xFF2AABEE).withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
          child: Text(code, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: 4, color: Color(0xFF2AABEE))),
        ),
        const SizedBox(height: 8),
        const Text('Отправьте код участникам', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 13)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Закрыть')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2AABEE)),
          onPressed: () {
            Navigator.pop(dialogCtx);
            _openConference(ctx, code, isHost: true);
          },
          child: const Text('Войти'),
        ),
      ],
    ));
  }

  void _joinConf(BuildContext ctx, String code) {
    if (code.isEmpty) return;
    Navigator.pop(ctx); // close dialog if open
    _openConference(ctx, code, isHost: false);
  }

  void _openConference(BuildContext ctx, String code, {bool isHost = false}) {
    Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => ConferenceScreen(
      roomCode: code,
      title: 'Конференция $code',
      isHost: isHost,
    )));
  }

  Widget _emptyState() {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.chat_bubble_outline, size: 80, color: const Color(0xFF8E8E93).withOpacity(0.4)),
      const SizedBox(height: 20),
      const Text('Нет чатов', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      const Text('Нажмите ✏️ чтобы начать переписку', style: TextStyle(color: Color(0xFF8E8E93))),
      const SizedBox(height: 24),
      ElevatedButton.icon(
        icon: const Icon(Icons.person_add),
        label: const Text('Найти пользователя'),
        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2AABEE)),
        onPressed: () => _showSearch(context),
      ),
    ]));
  }
}

class _UserSearchDelegate extends SearchDelegate<String> {
  final Dio dio;
  final String? myUserId;
  final VoidCallback onChatCreated;
  _UserSearchDelegate(this.dio, this.myUserId, this.onChatCreated);

  @override String get searchFieldLabel => 'Поиск пользователей...';
  @override List<Widget> buildActions(BuildContext ctx) => [IconButton(icon: const Icon(Icons.clear), onPressed: () => query = '')];
  @override Widget buildLeading(BuildContext ctx) => IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => close(ctx, ''));
  @override Widget buildResults(BuildContext ctx) => _buildList(ctx);
  @override Widget buildSuggestions(BuildContext ctx) => query.length < 2 ? const Center(child: Text('Введите минимум 2 символа')) : _buildList(ctx);

  Widget _buildList(BuildContext ctx) {
    return FutureBuilder(
      future: dio.get('/users/search', queryParameters: {'q': query}),
      builder: (ctx, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final users = List<dynamic>.from((snap.data as Response).data['users'] ?? []);
        if (users.isEmpty) return const Center(child: Text('Пользователи не найдены'));
        return ListView.builder(
          itemCount: users.length,
          itemBuilder: (_, i) {
            final u = users[i];
            final isSelf = u['_id'] == myUserId;
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: const Color(0xFF2AABEE).withOpacity(0.2),
                child: Text((u['name'] ?? '?')[0].toUpperCase(), style: const TextStyle(color: Color(0xFF2AABEE), fontWeight: FontWeight.w700)),
              ),
              title: Text(u['name'] ?? '?', style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('@${u['login'] ?? ''} • ${u['email'] ?? ''}'),
              trailing: isSelf ? const Chip(label: Text('Вы')) : const Icon(Icons.chevron_right, color: Color(0xFF2AABEE)),
              onTap: isSelf ? null : () async {
                try {
                  final r = await dio.post('/chats/direct', data: {'targetUserId': u['_id']});
                  final chatId = r.data['chat']['_id'];
                  final chatName = u['name'] ?? 'Чат';
                  close(ctx, '');
                  onChatCreated();
                  if (ctx.mounted) {
                    Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => ChatScreen(
                      chatId: chatId, chatName: chatName,
                      isOnline: u['online'] == true,
                      otherUserId: (u['_id'] ?? u['id'])?.toString() ?? '',
                    )));
                  }
                } catch (e) {
                  if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red));
                }
              },
            );
          },
        );
      },
    );
  }
}
