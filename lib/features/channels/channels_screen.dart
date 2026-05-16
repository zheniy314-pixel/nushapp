import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/config/app_config.dart';

class ChannelsScreen extends StatefulWidget {
  const ChannelsScreen({super.key});
  @override State<ChannelsScreen> createState() => _ChannelsScreenState();
}

class _ChannelsScreenState extends State<ChannelsScreen>
    with SingleTickerProviderStateMixin {
  final _storage = const FlutterSecureStorage();
  final _dio = Dio(BaseOptions(baseUrl: AppConfig.apiUrl));
  late final TabController _tabCtrl;

  static const _categories = [
    {'key': 'russia_news', 'label': 'Россия', 'icon': '🇷🇺'},
    {'key': 'svo_news',    'label': 'СВО',    'icon': '⚔️'},
    {'key': 'drone_tech',  'label': 'Дроны',  'icon': '🚁'},
    {'key': 'comp_tech',   'label': 'IT',      'icon': '💻'},
    {'key': 'animals_world','label': 'Животные','icon': '🐾'},
    {'key': 'auto_news',   'label': 'Авто',   'icon': '🚗'},
  ];

  List<dynamic> _posts = [];
  String _currentHandle = 'russia_news';
  bool _loading = false;
  String? _lastParsed;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _categories.length, vsync: this);
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging) {
        _currentHandle = _categories[_tabCtrl.index]['key']!;
        _loadPosts();
      }
    });
    _init();
  }

  Future<void> _init() async {
    final t = await _storage.read(key: 'access_token');
    if (t != null) _dio.options.headers['Authorization'] = 'Bearer $t';
    await _loadPosts();
  }

  Future<void> _loadPosts() async {
    setState(() => _loading = true);
    try {
      final r = await _dio.get('/channels/$_currentHandle/posts',
          queryParameters: {'page': 1, 'limit': 30});
      setState(() {
        _posts = List<dynamic>.from(r.data['posts'] ?? []);
        _lastParsed = r.data['lastParsedAt'];
      });
    } catch (_) {
      setState(() => _posts = []);
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    try {
      await _dio.post('/channels/$_currentHandle/refresh');
      await _loadPosts();
    } catch (_) {
      await _loadPosts();
    }
  }

  @override
  void dispose() { _tabCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Каналы'),
        actions: [
          IconButton(icon: const Icon(Icons.search), onPressed: () {}),
          IconButton(icon: const Icon(Icons.add), onPressed: () {}),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          isScrollable: true,
          labelColor: const Color(0xFF2AABEE),
          unselectedLabelColor: const Color(0xFF8E8E93),
          indicatorColor: const Color(0xFF2AABEE),
          tabs: _categories.map((c) => Tab(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(c['icon']!, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              Text(c['label']!),
            ]),
          )).toList(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _posts.isEmpty
              ? _emptyState()
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _posts.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
                    itemBuilder: (_, i) => _newsCard(_posts[i]),
                  ),
                ),
    );
  }

  Widget _newsCard(dynamic post) {
    final title = (post['title'] ?? '').toString();
    final text = (post['text'] ?? '').toString();
    final imageUrl = post['imageUrl'] as String?;
    final sourceUrl = post['sourceUrl'] as String?;
    final sourceName = (post['sourceName'] ?? '').toString();
    final date = _formatDate(post['publishedAt'] as String?);
    final views = post['viewCount'] ?? 0;

    return InkWell(
      onTap: () => _openNews(post),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Заголовок
          if (title.isNotEmpty)
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, height: 1.3)),

          // Изображение
          if (imageUrl != null && imageUrl.isNotEmpty) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: imageUrl, width: double.infinity, height: 200, fit: BoxFit.cover,
                errorWidget: (_, __, ___) => const SizedBox(),
                placeholder: (_, __) => Container(height: 200, color: const Color(0xFFF5F5F5)),
              ),
            ),
          ],

          const SizedBox(height: 8),

          // Текст превью
          if (text.isNotEmpty && text != title)
            Text(text.length > 200 ? '${text.substring(0, 200)}...' : text,
                style: const TextStyle(fontSize: 14, color: Color(0xFF3A3A3C), height: 1.4)),

          const SizedBox(height: 8),

          // Метаданные + реакции
          Row(children: [
            if (sourceName.isNotEmpty) ...[
              Text(sourceName, style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E93))),
              const Text(' · ', style: TextStyle(fontSize: 11, color: Color(0xFF8E8E93))),
            ],
            Text(date, style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E93))),
            const Spacer(),
            const Icon(Icons.visibility_outlined, size: 12, color: Color(0xFF8E8E93)),
            const SizedBox(width: 3),
            Text('$views', style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E93))),
            const SizedBox(width: 12),
            _reactionRow(post),
          ]),

          // Кнопка "Читать далее"
          if (sourceUrl != null && sourceUrl.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: TextButton.icon(
                icon: const Icon(Icons.open_in_new, size: 14),
                label: const Text('Читать полностью'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF2AABEE),
                  padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => _openUrl(sourceUrl),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _reactionRow(dynamic post) {
    final reactions = (post['reactions'] as List?) ?? [];
    if (reactions.isEmpty) {
      return GestureDetector(
        onTap: () {},
        child: const Text('👍', style: TextStyle(fontSize: 18)),
      );
    }
    return Row(mainAxisSize: MainAxisSize.min, children: reactions.take(3).map((r) {
      return Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Text('${r['emoji']}${r['count']}', style: const TextStyle(fontSize: 12)),
      );
    }).toList());
  }

  void _openNews(dynamic post) {
    final sourceUrl = post['sourceUrl'] as String?;
    if (sourceUrl != null) _openUrl(sourceUrl);
    else _showDetail(post);
  }

  void _showDetail(dynamic post) {
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false, initialChildSize: 0.85,
        builder: (_, ctrl) => SingleChildScrollView(
          controller: ctrl,
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(post['title'] ?? '', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Text(post['text'] ?? '', style: const TextStyle(fontSize: 15, height: 1.6)),
          ]),
        ),
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _emptyState() {
    final cat = _categories.firstWhere((c) => c['key'] == _currentHandle, orElse: () => _categories[0]);
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(cat['icon']!, style: const TextStyle(fontSize: 64)),
        const SizedBox(height: 16),
        Text('Загружаем новости ${cat['label']}...',
            style: const TextStyle(fontSize: 16, color: Color(0xFF8E8E93))),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: _refresh,
          icon: const Icon(Icons.refresh),
          label: const Text('Обновить'),
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2AABEE)),
        ),
      ]),
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    final d = DateTime.tryParse(dateStr);
    if (d == null) return '';
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inMinutes < 60) return '${diff.inMinutes} мин назад';
    if (diff.inHours < 24) return '${diff.inHours} ч назад';
    return '${d.day}.${d.month.toString().padLeft(2, '0')}';
  }
}
