import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/config/app_config.dart';
import 'chat_screen.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});
  @override State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _storage = const FlutterSecureStorage();
  final _dio = Dio(BaseOptions(baseUrl: AppConfig.apiUrl));
  final _titleCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  List<dynamic> _searchResults = [];
  List<dynamic> _selected = [];
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _initToken();
  }

  Future<void> _initToken() async {
    final t = await _storage.read(key: 'access_token');
    if (t != null) _dio.options.headers['Authorization'] = 'Bearer $t';
  }

  Future<void> _search(String q) async {
    if (q.length < 2) { setState(() => _searchResults = []); return; }
    try {
      final r = await _dio.get('/users/search', queryParameters: {'q': q});
      setState(() => _searchResults = List<dynamic>.from(r.data['users'] ?? []));
    } catch (_) {}
  }

  void _toggleUser(dynamic user) {
    setState(() {
      final idx = _selected.indexWhere((u) => u['_id'] == user['_id']);
      if (idx >= 0) _selected.removeAt(idx);
      else _selected.add(user);
    });
  }

  bool _isSelected(dynamic user) => _selected.any((u) => u['_id'] == user['_id']);

  Future<void> _create() async {
    if (_titleCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Введите название группы')));
      return;
    }
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Добавьте хотя бы одного участника')));
      return;
    }
    setState(() => _creating = true);
    try {
      final r = await _dio.post('/chats/group', data: {
        'title': _titleCtrl.text.trim(),
        'memberIds': _selected.map((u) => u['_id']).toList(),
      });
      final chatId = r.data['chat']['_id'];
      final name = r.data['chat']['title'];
      if (mounted) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ChatScreen(chatId: chatId, chatName: name, isOnline: true)));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red));
    } finally {
      setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Создать группу'),
        actions: [
          TextButton(
            onPressed: _creating || _selected.isEmpty ? null : _create,
            child: _creating
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF2AABEE)))
                : const Text('Создать', style: TextStyle(color: Color(0xFF2AABEE), fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: Column(
        children: [
          // Название группы
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _titleCtrl,
              decoration: InputDecoration(
                labelText: 'Название группы',
                prefixIcon: Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.deepPurple, borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.group, color: Colors.white, size: 20),
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),

          // Выбранные участники
          if (_selected.isNotEmpty)
            Container(
              height: 80,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _selected.length,
                itemBuilder: (_, i) {
                  final u = _selected[i];
                  return Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Column(
                      children: [
                        Stack(
                          children: [
                            CircleAvatar(radius: 24, backgroundColor: Colors.deepPurple.withOpacity(0.2),
                              child: Text((u['name'] ?? '?')[0].toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.deepPurple))),
                            Positioned(right: 0, top: 0,
                              child: GestureDetector(
                                onTap: () => _toggleUser(u),
                                child: Container(width: 18, height: 18,
                                  decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                                  child: const Icon(Icons.close, size: 12, color: Colors.white)),
                              )),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(u['name'] ?? '?', style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  );
                },
              ),
            ),

          const Divider(),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4), child: Text('УЧАСТНИКИ', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1))),

          // Поиск
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _search,
              decoration: InputDecoration(
                hintText: 'Поиск пользователей...',
                prefixIcon: const Icon(Icons.search),
                filled: true, fillColor: const Color(0xFFF5F5F5),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ),

          // Список
          Expanded(
            child: _searchResults.isEmpty
                ? const Center(child: Text('Введите имя или логин для поиска', style: TextStyle(color: Color(0xFF8E8E93))))
                : ListView.builder(
                    itemCount: _searchResults.length,
                    itemBuilder: (_, i) {
                      final u = _searchResults[i];
                      final sel = _isSelected(u);
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: sel ? Colors.deepPurple.withOpacity(0.2) : const Color(0xFF2AABEE).withOpacity(0.15),
                          child: sel
                              ? const Icon(Icons.check, color: Colors.deepPurple)
                              : Text((u['name'] ?? '?')[0].toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                        title: Text(u['name'] ?? '?', style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text('@${u['login'] ?? ''}'),
                        trailing: sel ? const Icon(Icons.check_circle, color: Colors.deepPurple) : const Icon(Icons.circle_outlined, color: Color(0xFF8E8E93)),
                        selected: sel,
                        onTap: () => _toggleUser(u),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() { _titleCtrl.dispose(); _searchCtrl.dispose(); super.dispose(); }
}
