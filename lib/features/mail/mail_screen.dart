import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/config/app_config.dart';

class MailScreen extends StatefulWidget {
  const MailScreen({super.key});

  @override
  State<MailScreen> createState() => _MailScreenState();
}

class _MailScreenState extends State<MailScreen>
    with SingleTickerProviderStateMixin {
  final _storage = const FlutterSecureStorage();
  late final TabController _tabCtrl;
  final _dio = Dio(BaseOptions(baseUrl: AppConfig.apiUrl));

  final List<String> _folders = ['inbox', 'sent', 'drafts', 'archive', 'trash'];
  final List<String> _folderLabels = ['Входящие', 'Отправленные', 'Черновики', 'Архив', 'Корзина'];
  String _currentFolder = 'inbox';
  List<dynamic> _mails = [];
  bool _loading = false;
  Map<String, dynamic> _folderCounts = {};
  String? _myAddress;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _folders.length, vsync: this);
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging) {
        setState(() => _currentFolder = _folders[_tabCtrl.index]);
        _loadMails();
      }
    });
    _init();
  }

  Future<void> _init() async {
    final token = await _storage.read(key: 'access_token');
    if (token != null) _dio.options.headers['Authorization'] = 'Bearer $token';
    await Future.wait([_loadFolders(), _loadMails(), _loadMyAddress()]);
  }

  Future<void> _loadMyAddress() async {
    try {
      final r = await _dio.get('/mail/address/mine');
      setState(() => _myAddress = r.data['nusha_address']);
    } catch (_) {}
  }

  Future<void> _loadFolders() async {
    try {
      final r = await _dio.get('/mail/folders');
      setState(() => _folderCounts = Map<String, dynamic>.from(r.data['folders'] ?? {}));
    } catch (_) {}
  }

  Future<void> _loadMails() async {
    setState(() => _loading = true);
    try {
      final r = await _dio.get('/mail/$_currentFolder');
      setState(() => _mails = List<dynamic>.from(r.data['mails'] ?? []));
    } catch (_) {
      setState(() => _mails = []);
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final unreadInbox = (_folderCounts['inbox'] as Map?)?['unread'] ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Почта', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            if (_myAddress != null)
              Text(_myAddress!, style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93))),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.search), onPressed: () {}),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadMails),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          isScrollable: true,
          labelColor: const Color(0xFF2AABEE),
          unselectedLabelColor: const Color(0xFF8E8E93),
          indicatorColor: const Color(0xFF2AABEE),
          tabs: List.generate(_folders.length, (i) {
            final folder = _folders[i];
            final count = (_folderCounts[folder] as Map?)?['unread'] ?? 0;
            return Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_folderLabels[i], style: const TextStyle(fontSize: 13)),
                  if (count > 0) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: const Color(0xFF2AABEE), borderRadius: BorderRadius.circular(10)),
                      child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 10)),
                    ),
                  ],
                ],
              ),
            );
          }),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _mails.isEmpty
              ? _emptyState()
              : RefreshIndicator(
                  onRefresh: _loadMails,
                  child: ListView.separated(
                    itemCount: _mails.length,
                    separatorBuilder: (_, __) => const Divider(height: 0, indent: 72),
                    itemBuilder: (_, i) => _mailTile(_mails[i]),
                  ),
                ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF2AABEE),
        child: const Icon(Icons.edit, color: Colors.white),
        onPressed: () => _openCompose(),
      ),
    );
  }

  Widget _mailTile(dynamic mail) {
    final isRead = mail['isRead'] == true;
    final fromMap = mail['from'] as Map? ?? {};
    final from = (fromMap['name'] ?? fromMap['address'] ?? 'Неизвестно').toString();
    final subject = mail['subject'] ?? '(Без темы)';
    final preview = mail['bodyText']?.toString().replaceAll('\n', ' ') ?? '';
    final date = _formatDate(mail['createdAt']);
    final isStarred = mail['isStarred'] == true;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: const Color(0xFF2AABEE).withOpacity(0.15),
        child: Text(
          from.isNotEmpty ? from[0].toUpperCase() : '?',
          style: const TextStyle(color: Color(0xFF2AABEE), fontWeight: FontWeight.w600),
        ),
      ),
      title: Row(
        children: [
          Expanded(child: Text(from,
            style: TextStyle(fontWeight: isRead ? FontWeight.w400 : FontWeight.w700, fontSize: 15),
            maxLines: 1, overflow: TextOverflow.ellipsis)),
          Text(date, style: TextStyle(fontSize: 12,
            color: isRead ? const Color(0xFF8E8E93) : const Color(0xFF2AABEE))),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(subject, style: TextStyle(fontWeight: isRead ? FontWeight.w400 : FontWeight.w600, fontSize: 14),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(preview, style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 13),
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
      trailing: isStarred ? const Icon(Icons.star, color: Colors.amber, size: 18) : null,
      isThreeLine: true,
      onTap: () => _openMail(mail),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.mail_outline, size: 64, color: Color(0xFF8E8E93)),
          const SizedBox(height: 16),
          Text('Нет писем в ${_folderLabels[_tabCtrl.index].toLowerCase()}',
              style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 16)),
        ],
      ),
    );
  }

  void _openMail(dynamic mail) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => MailDetailScreen(mail: mail)));
  }

  void _openCompose() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ComposeMailScreen(dio: _dio)));
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    final date = DateTime.tryParse(dateStr);
    if (date == null) return '';
    final now = DateTime.now();
    if (date.year == now.year && date.month == now.month && date.day == now.day) {
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    }
    return '${date.day}.${date.month.toString().padLeft(2, '0')}';
  }
}

// ─── Экран просмотра письма ───────────────────────────────────────────────────
class MailDetailScreen extends StatelessWidget {
  final dynamic mail;
  const MailDetailScreen({super.key, required this.mail});

  @override
  Widget build(BuildContext context) {
    final subject = mail['subject'] ?? '(Без темы)';
    final fromMap2 = mail['from'] as Map? ?? {};
    final from = (fromMap2['address'] ?? '').toString();
    final fromName = (fromMap2['name'] ?? from).toString();
    final body = mail['bodyText'] ?? mail['bodyHtml'] ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text(subject, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(icon: const Icon(Icons.reply), onPressed: () {}),
          IconButton(icon: const Icon(Icons.star_border), onPressed: () {}),
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: () {}),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(subject, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: const Color(0xFF2AABEE).withOpacity(0.15),
                  child: Text(fromName.isNotEmpty ? fromName[0].toUpperCase() : '?',
                      style: const TextStyle(color: Color(0xFF2AABEE))),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(fromName, style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(from, style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Text(body, style: const TextStyle(fontSize: 15, height: 1.5)),
          ],
        ),
      ),
    );
  }
}

// ─── Экран написания письма ───────────────────────────────────────────────────
class ComposeMailScreen extends StatefulWidget {
  final Dio dio;
  const ComposeMailScreen({super.key, required this.dio});

  @override
  State<ComposeMailScreen> createState() => _ComposeMailScreenState();
}

class _ComposeMailScreenState extends State<ComposeMailScreen> {
  final _toCtrl = TextEditingController();
  final _subjectCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  bool _sending = false;

  Future<void> _send() async {
    if (_toCtrl.text.trim().isEmpty) return;
    setState(() => _sending = true);
    try {
      await widget.dio.post('/mail/send', data: {
        'to': _toCtrl.text.trim().split(',').map((e) => e.trim()).toList(),
        'subject': _subjectCtrl.text.trim(),
        'bodyText': _bodyCtrl.text,
        'bodyHtml': _bodyCtrl.text,
      });
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка отправки: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Новое письмо'),
        actions: [
          if (_sending)
            const Center(child: Padding(padding: EdgeInsets.all(16), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))))
          else
            IconButton(icon: const Icon(Icons.send, color: Color(0xFF2AABEE)), onPressed: _send),
        ],
      ),
      body: Column(
        children: [
          _headerField('Кому', _toCtrl, TextInputType.emailAddress),
          const Divider(height: 0),
          _headerField('Тема', _subjectCtrl, TextInputType.text),
          const Divider(height: 0),
          Expanded(
            child: TextField(
              controller: _bodyCtrl,
              maxLines: null,
              expands: true,
              keyboardType: TextInputType.multiline,
              textAlignVertical: TextAlignVertical.top,
              decoration: const InputDecoration(
                hintText: 'Текст письма...',
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerField(String label, TextEditingController ctrl, TextInputType type) {
    return Row(
      children: [
        SizedBox(width: 80, child: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Text(label, style: const TextStyle(color: Color(0xFF8E8E93))),
        )),
        Expanded(child: TextField(
          controller: ctrl,
          keyboardType: type,
          decoration: const InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.all(16)),
        )),
      ],
    );
  }

  @override
  void dispose() {
    _toCtrl.dispose(); _subjectCtrl.dispose(); _bodyCtrl.dispose();
    super.dispose();
  }
}
