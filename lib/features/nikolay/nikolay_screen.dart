import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';

class NikolayScreen extends StatefulWidget {
  const NikolayScreen({super.key});

  @override
  State<NikolayScreen> createState() => _NikolayScreenState();
}

class _NikolayScreenState extends State<NikolayScreen>
    with SingleTickerProviderStateMixin {
  late final Dio _dio;
  late final AnimationController _motion;
  final _taskCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  bool _loading = true;
  bool _busy = false;
  bool _coreOnline = false;
  bool _internetEnabled = true;
  Map<String, dynamic>? _project;
  Map<String, dynamic>? _settings;
  List<dynamic> _projects = [];
  final List<_ChatMessage> _messages = [];

  @override
  void initState() {
    super.initState();
    _dio = Dio(BaseOptions(
      baseUrl: AppConfig.nikolayCoreUrl,
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 180),
    ));
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
    _bootstrap();
  }

  @override
  void dispose() {
    _motion.dispose();
    _taskCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() => _loading = true);
    try {
      await _dio.get('/health');
      _coreOnline = true;
      final settings = await _dio.get('/settings');
      _settings = Map<String, dynamic>.from(settings.data);
      _internetEnabled = _settings?['internet_enabled'] != false;
      final projects = await _dio.get('/projects');
      _projects = List<dynamic>.from(projects.data['projects'] ?? []);
      if (_projects.isEmpty) {
        await _createProject();
      } else {
        _project = Map<String, dynamic>.from(_projects.first);
        _hello();
      }
    } catch (e) {
      _coreOnline = false;
      _messages
        ..clear()
        ..add(_ChatMessage.assistant(
          'Ядро Nikolay Core пока не отвечает. Запустите сервер на '
          '${AppConfig.nikolayCoreUrl}, и интерфейс сразу подключится.',
        ));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _hello() {
    if (_messages.isNotEmpty || _project == null) return;
    _messages.add(_ChatMessage.assistant(
      'Создана чистая рабочая среда "${_project!['name']}". '
      'Загрузите книги/методологии в базу знаний. Excel/XML/CSV загружайте отдельно как файлы анализа.',
    ));
  }

  Future<void> _createProject() async {
    final name = 'Проект Николая ${DateTime.now().toString().substring(0, 16)}';
    final response = await _dio.post('/projects', data: {'name': name});
    _project = Map<String, dynamic>.from(response.data['project']);
    final projects = await _dio.get('/projects');
    _projects = List<dynamic>.from(projects.data['projects'] ?? []);
    _messages
      ..clear()
      ..add(_ChatMessage.assistant(
        'Новый диалог создан как чистая копия. Старые знания сюда не попадают.',
      ));
  }

  Future<void> _refreshProject() async {
    final id = _project?['id'];
    if (id == null) return;
    final response = await _dio.get('/projects/$id');
    setState(() => _project = Map<String, dynamic>.from(response.data['project']));
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      setState(() => _messages.add(_ChatMessage.assistant('Ошибка: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
      _scrollDown();
    }
  }

  Future<void> _pickAndUpload(String category) async {
    if (_project == null) return;
    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const [
        'pdf',
        'docx',
        'xlsx',
        'xls',
        'txt',
        'md',
        'csv',
        'html',
        'htm',
        'json',
        'xml',
      ],
    );
    if (picked == null || picked.files.isEmpty) return;

    await _run(() async {
      for (final file in picked.files) {
        if (file.path == null) continue;
        final data = FormData.fromMap({
          'category': category,
          'file': await MultipartFile.fromFile(file.path!, filename: file.name),
        });
        await _dio.post('/projects/${_project!['id']}/files', data: data);
      }
      await _refreshProject();
      setState(() => _messages.add(_ChatMessage.assistant(
        'Файлы загружены в раздел "${_categoryTitle(category)}". '
        '${category == 'knowledge' || category == 'methodology' ? 'Это попадет в индекс знаний.' : 'Это файл анализа, он не засоряет память проекта.'}',
      )));
    });
  }

  Future<void> _indexProject() async {
    if (_project == null) return;
    await _run(() async {
      setState(() => _messages.add(_ChatMessage.assistant(
        'Начинаю индексацию только базы знаний: книги, методологии и правила. Файлы анализа не индексируются как память.',
      )));
      final response = await _dio.post('/projects/${_project!['id']}/index');
      final project = Map<String, dynamic>.from(response.data['project']);
      final summary = Map<String, dynamic>.from(project['knowledge_summary'] ?? {});
      setState(() {
        _project = project;
        _messages.add(_ChatMessage.assistant(
          'Индексация завершена. Документов: ${summary['documents'] ?? 0}, '
          'фрагментов: ${summary['chunks'] ?? 0}. Теперь можно давать ТЗ.',
        ));
      });
    });
  }

  Future<void> _sendTask() async {
    final text = _taskCtrl.text.trim();
    if (text.isEmpty || _project == null) return;
    _taskCtrl.clear();
    setState(() => _messages.add(_ChatMessage.user(text)));
    await _run(() async {
      final response = await _dio.post('/projects/${_project!['id']}/chat', data: {
        'prompt': text,
        'use_internet': _internetEnabled,
        'create_pdf': true,
      });
      final report = Map<String, dynamic>.from(response.data['report']);
      await _refreshProject();
      setState(() => _messages.add(_ChatMessage.assistant(
        response.data['message'] ?? 'Отчет готов.',
        report: report,
      )));
    });
  }

  Future<void> _openReport(String kind, Map<String, dynamic> report) async {
    final path = kind == 'pdf' ? report['pdf_url'] : report['html_url'];
    if (path == null) return;
    final uri = Uri.parse('${AppConfig.nikolayCoreUrl}$path');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _saveSettings({
    required String ollamaUrl,
    required String ollamaModel,
    required String title,
    required bool internetEnabled,
  }) async {
    await _run(() async {
      final response = await _dio.put('/settings', data: {
        'llm_provider': 'ollama',
        'ollama_url': ollamaUrl,
        'ollama_model': ollamaModel,
        'internet_enabled': internetEnabled,
        'index_chunk_chars': _settings?['index_chunk_chars'] ?? 1200,
        'report_title': title,
      });
      setState(() {
        _settings = Map<String, dynamic>.from(response.data);
        _internetEnabled = internetEnabled;
        _messages.add(_ChatMessage.assistant('Настройки сохранены.'));
      });
    });
  }

  void _scrollDown() {
    Future.delayed(const Duration(milliseconds: 120), () {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    });
  }

  String _categoryTitle(String category) {
    switch (category) {
      case 'methodology':
        return 'Методологии';
      case 'data':
        return 'Файлы анализа Excel/CSV';
      case 'template':
        return 'Шаблоны отчетов';
      case 'task':
        return 'Файлы к заданию';
      default:
        return 'Книги и знания';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;
    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF17212B)
          : const Color(0xFFEFF6FB),
      appBar: AppBar(
        titleSpacing: 12,
        title: Row(
          children: [
            _PulsingLogo(animation: _motion),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Николай', style: TextStyle(fontWeight: FontWeight.w700)),
                Text('нейросимволическая машина',
                    style: TextStyle(fontSize: 12, color: Color(0xFF8E8E93))),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Новый чистый проект',
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: _busy ? null : () => _run(_createProject),
          ),
          IconButton(
            tooltip: 'Настройки',
            icon: const Icon(Icons.tune),
            onPressed: _showSettings,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: isWide
                    ? Row(
                        children: [
                          SizedBox(width: 330, child: _buildSidePanel()),
                          Expanded(child: _buildChatPanel()),
                        ],
                      )
                    : Column(
                        children: [
                          _buildMobileProjectBar(),
                          Expanded(child: _buildChatPanel()),
                        ],
                      ),
              ),
            ),
    );
  }

  Widget _buildSidePanel() {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: _buildProjectSummary(),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(14),
            child: _buildActionGrid(),
          ),
          const Divider(height: 1),
          Expanded(child: _buildProjectsList()),
        ],
      ),
    );
  }

  Widget _buildMobileProjectBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Column(
        children: [
          _buildProjectSummary(compact: true),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: _actionButtons(compact: true)),
          ),
        ],
      ),
    );
  }

  Widget _buildProjectSummary({bool compact = false}) {
    final files = List<dynamic>.from(_project?['files'] ?? []);
    final summary = Map<String, dynamic>.from(_project?['knowledge_summary'] ?? {});
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      padding: EdgeInsets.all(compact ? 14 : 0),
      decoration: compact
          ? BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(22),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _project?['name'] ?? 'Проект не создан',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ),
              _StatusDot(online: _coreOnline),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoChip(icon: Icons.folder_copy_outlined, text: '${files.length} файлов'),
              _InfoChip(
                icon: Icons.auto_awesome_motion,
                text: '${summary['chunks'] ?? 0} фрагментов',
              ),
              _InfoChip(
                icon: _internetEnabled ? Icons.public : Icons.public_off,
                text: _internetEnabled ? 'интернет вкл.' : 'интернет выкл.',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionGrid() {
    return Wrap(spacing: 8, runSpacing: 8, children: _actionButtons());
  }

  List<Widget> _actionButtons({bool compact = false}) {
    final buttons = [
      _ActionButton(
        icon: Icons.menu_book_outlined,
        title: compact ? 'Книги' : 'Книги',
        onTap: () => _pickAndUpload('knowledge'),
      ),
      _ActionButton(
        icon: Icons.account_tree_outlined,
        title: compact ? 'Метод' : 'Методологии',
        onTap: () => _pickAndUpload('methodology'),
      ),
      _ActionButton(
        icon: Icons.table_chart_outlined,
        title: compact ? 'Анализ' : 'Файлы анализа',
        onTap: () => _pickAndUpload('data'),
      ),
      _ActionButton(
        icon: Icons.description_outlined,
        title: compact ? 'Шаблон' : 'Шаблон',
        onTap: () => _pickAndUpload('template'),
      ),
      _ActionButton(
        icon: Icons.bolt_outlined,
        title: compact ? 'Индекс' : 'Индекс знаний',
        accent: true,
        onTap: _indexProject,
      ),
    ];
    return buttons
        .map((button) => Padding(
              padding: compact ? const EdgeInsets.only(right: 8) : EdgeInsets.zero,
              child: button,
            ))
        .toList();
  }

  Widget _buildProjectsList() {
    if (_projects.isEmpty) {
      return const Center(child: Text('Проектов пока нет'));
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _projects.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final project = Map<String, dynamic>.from(_projects[i]);
        final active = project['id'] == _project?['id'];
        return ListTile(
          selected: active,
          leading: CircleAvatar(
            backgroundColor: active ? const Color(0xFF2AABEE) : const Color(0xFFE5E5EA),
            child: Icon(Icons.psychology_alt, color: active ? Colors.white : Colors.black54),
          ),
          title: Text(project['name'] ?? 'Проект'),
          subtitle: Text('${project['status'] ?? 'empty'} · ${project['created_at'] ?? ''}'),
          onTap: () {
            setState(() {
              _project = project;
              _messages
                ..clear()
                ..add(_ChatMessage.assistant(
                  'Открыт проект "${project['name']}". Его база знаний изолирована.',
                ));
            });
          },
        );
      },
    );
  }

  Widget _buildChatPanel() {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF0E1621)
            : const Color(0xFFDDEBF6),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(
        children: [
          _buildMotionStrip(),
          Expanded(
            child: _messages.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 14),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) => _buildBubble(_messages[i]),
                  ),
          ),
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildMotionStrip() {
    return AnimatedBuilder(
      animation: _motion,
      builder: (_, __) {
        final t = _motion.value * math.pi * 2;
        return Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Transform.translate(
                offset: Offset(math.sin(t) * 3, 0),
                child: const Icon(Icons.hub_outlined, color: Color(0xFF2AABEE)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _busy
                      ? 'Николай выполняет задачу...'
                      : 'Индексируйте знания отдельно, файлы анализа прикладывайте к задаче',
                  style: const TextStyle(color: Color(0xFF667785), fontSize: 13),
                ),
              ),
              Switch(
                value: _internetEnabled,
                activeColor: const Color(0xFF2AABEE),
                onChanged: _busy ? null : (v) => setState(() => _internetEnabled = v),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PulsingLogo(animation: _motion, large: true),
            const SizedBox(height: 18),
            const Text(
              'Николай готов к обучению проекта',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Каждый новый диалог получает чистую память. '
              'Знания появляются только после загрузки и индексации файлов.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF667785)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBubble(_ChatMessage message) {
    final isUser = message.role == 'user';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isUser
        ? (isDark ? const Color(0xFF2B5278) : const Color(0xFFEFFDDE))
        : (isDark ? const Color(0xFF182533) : Colors.white);
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isUser ? 18 : 5),
            bottomRight: Radius.circular(isUser ? 5 : 18),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message.text, style: const TextStyle(fontSize: 15, height: 1.35)),
            if (message.report != null) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _openReport('html', message.report!),
                    icon: const Icon(Icons.language, size: 18),
                    label: const Text('HTML'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _openReport('pdf', message.report!),
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                    label: const Text('PDF'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: EdgeInsets.only(
        left: 10,
        right: 10,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 10,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF17212B) : Colors.white,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(26)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: _busy ? null : () => _showUploadSheet(),
            icon: const Icon(Icons.attach_file, color: Color(0xFF8E8E93)),
          ),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF242F3D) : const Color(0xFFF4F7FA),
                borderRadius: BorderRadius.circular(22),
              ),
              child: TextField(
                controller: _taskCtrl,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  hintText: 'Дайте ТЗ Николаю...',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: _busy ? const Color(0xFF8E8E93) : const Color(0xFF2AABEE),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              onPressed: _busy ? null : _sendTask,
              icon: Icon(_busy ? Icons.hourglass_empty : Icons.send, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _showUploadSheet() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.menu_book_outlined, color: Color(0xFF2AABEE)),
              title: const Text('Загрузить книги и знания'),
              onTap: () {
                Navigator.pop(context);
                _pickAndUpload('knowledge');
              },
            ),
            ListTile(
              leading: const Icon(Icons.account_tree_outlined, color: Color(0xFF2AABEE)),
              title: const Text('Загрузить методологии'),
              onTap: () {
                Navigator.pop(context);
                _pickAndUpload('methodology');
              },
            ),
            ListTile(
              leading: const Icon(Icons.table_chart_outlined, color: Color(0xFF2AABEE)),
              title: const Text('Загрузить файлы анализа Excel/CSV/XML'),
              onTap: () {
                Navigator.pop(context);
                _pickAndUpload('data');
              },
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined, color: Color(0xFF2AABEE)),
              title: const Text('Загрузить HTML-шаблон отчета'),
              onTap: () {
                Navigator.pop(context);
                _pickAndUpload('template');
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showSettings() {
    final ollamaUrl = TextEditingController(
      text: _settings?['ollama_url'] ?? 'http://127.0.0.1:11434',
    );
    final ollamaModel = TextEditingController(
      text: _settings?['ollama_model'] ?? 'llama3.1',
    );
    final title = TextEditingController(
      text: _settings?['report_title'] ?? 'НС "НИКОЛАЙ" | ЕДИНЫЙ АНАЛИТИЧЕСКИЙ ОТЧЕТ',
    );
    bool internet = _internetEnabled;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 18,
            right: 18,
            bottom: MediaQuery.of(context).viewInsets.bottom + 18,
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Настройки Николая',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 14),
                TextField(
                  controller: ollamaUrl,
                  decoration: const InputDecoration(labelText: 'Ollama URL'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: ollamaModel,
                  decoration: const InputDecoration(labelText: 'Модель'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: 'Заголовок отчета'),
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Разрешить интернет-поиск'),
                  subtitle: const Text('Николай будет искать недостающие источники'),
                  value: internet,
                  activeColor: const Color(0xFF2AABEE),
                  onChanged: (v) => setSheetState(() => internet = v),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _saveSettings(
                      ollamaUrl: ollamaUrl.text.trim(),
                      ollamaModel: ollamaModel.text.trim(),
                      title: title.text.trim(),
                      internetEnabled: internet,
                    );
                  },
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Сохранить настройки'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatMessage {
  final String role;
  final String text;
  final Map<String, dynamic>? report;

  _ChatMessage(this.role, this.text, {this.report});

  factory _ChatMessage.user(String text) => _ChatMessage('user', text);

  factory _ChatMessage.assistant(String text, {Map<String, dynamic>? report}) {
    return _ChatMessage('assistant', text, report: report);
  }
}

class _PulsingLogo extends StatelessWidget {
  final Animation<double> animation;
  final bool large;

  const _PulsingLogo({required this.animation, this.large = false});

  @override
  Widget build(BuildContext context) {
    final size = large ? 74.0 : 38.0;
    return AnimatedBuilder(
      animation: animation,
      builder: (_, __) {
        final scale = 1 + math.sin(animation.value * math.pi * 2) * 0.04;
        return Transform.scale(
          scale: scale,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF2AABEE), Color(0xFF74D5FF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF2AABEE).withOpacity(0.35),
                  blurRadius: 18,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(Icons.psychology_alt, color: Colors.white, size: large ? 40 : 22),
          ),
        );
      },
    );
  }
}

class _StatusDot extends StatelessWidget {
  final bool online;

  const _StatusDot({required this.online});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: online ? const Color(0xFF31C48D) : const Color(0xFFE02424),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          online ? 'ядро онлайн' : 'ядро офлайн',
          style: const TextStyle(color: Color(0xFF667785), fontSize: 12),
        ),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF2AABEE).withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: const Color(0xFF2AABEE)),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontSize: 12, color: Color(0xFF38657D))),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool accent;

  const _ActionButton({
    required this.icon,
    required this.title,
    required this.onTap,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = accent ? const Color(0xFF2AABEE) : Theme.of(context).colorScheme.surface;
    final fg = accent ? Colors.white : const Color(0xFF2AABEE);
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF2AABEE).withOpacity(0.18)),
          boxShadow: [
            if (accent)
              BoxShadow(
                color: const Color(0xFF2AABEE).withOpacity(0.25),
                blurRadius: 14,
                offset: const Offset(0, 7),
              ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: fg, size: 18),
            const SizedBox(width: 7),
            Text(title, style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
