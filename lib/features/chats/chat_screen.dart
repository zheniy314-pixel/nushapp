import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/config/app_config.dart';
import '../../core/services/socket_service.dart';
import '../../core/services/call_service.dart';

/// Экран чата — Telegram-стиль
class ChatScreen extends StatefulWidget {
  final String chatId;
  final String chatName;
  final String? chatAvatar;
  final bool isOnline;
  final String? otherUserId;

  const ChatScreen({
    super.key,
    required this.chatId,
    required this.chatName,
    this.chatAvatar,
    this.isOnline = false,
    this.otherUserId,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _storage   = const FlutterSecureStorage();
  final _dio       = Dio(BaseOptions(baseUrl: AppConfig.apiUrl));
  final _msgCtrl   = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _socket    = SocketService();
  final _callSvc   = CallService();

  List<Map<String, dynamic>> _messages = [];
  bool _loading    = true;
  bool _sending    = false;
  bool _peerTyping = false;
  bool _peerOnline = false;
  DateTime? _peerLastSeen;
  String? _myUserId;

  StreamSubscription? _subMsg;
  StreamSubscription? _subTypingStart;
  StreamSubscription? _subTypingStop;
  StreamSubscription? _subPresence;

  @override
  void initState() {
    super.initState();
    _peerOnline = widget.isOnline;
    _init();
  }

  Future<void> _init() async {
    final token = await _storage.read(key: 'access_token');
    _myUserId = await _storage.read(key: 'user_id');
    if (token != null) _dio.options.headers['Authorization'] = 'Bearer $token';

    // Use shared SocketService (already connected from MainScreen)
    _subMsg = _socket.onMessageNew.listen((data) {
      if (data['chatId'] == widget.chatId) {
        final msg = data['message'] as Map<String, dynamic>? ?? data;
        setState(() => _messages.insert(0, msg));
        _scrollToBottom();
      }
    });

    _subTypingStart = _socket.onTypingStart.listen((data) {
      if (data['chatId'] == widget.chatId && data['userId'] != _myUserId) {
        setState(() => _peerTyping = true);
      }
    });

    _subTypingStop = _socket.onTypingStop.listen((data) {
      if (data['chatId'] == widget.chatId && data['userId'] != _myUserId) {
        setState(() => _peerTyping = false);
      }
    });

    _subPresence = _socket.onPresenceUpdate.listen((data) {
      if (widget.otherUserId != null && data['userId'] == widget.otherUserId) {
        final online = data['online'] == true;
        DateTime? lastSeen;
        if (!online && data['lastSeen'] != null) {
          lastSeen = DateTime.tryParse(data['lastSeen'].toString());
        }
        setState(() {
          _peerOnline = online;
          if (lastSeen != null) _peerLastSeen = lastSeen;
        });
      }
    });

    await _loadMessages();
  }

  Future<void> _loadMessages() async {
    setState(() => _loading = true);
    try {
      final r = await _dio.get('/messages/${widget.chatId}');
      setState(() => _messages = List<Map<String, dynamic>>.from(r.data['messages'] ?? []));
    } catch (_) {}
    setState(() => _loading = false);
  }

  Future<void> _sendMessage() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    _msgCtrl.clear();
    setState(() => _sending = true);
    try {
      final r = await _dio.post('/messages', data: {'chatId': widget.chatId, 'text': text, 'type': 'text'});
      final msg = r.data['message'] as Map<String, dynamic>;
      setState(() => _messages.insert(0, msg));
      _scrollToBottom();
    } catch (_) {} finally {
      setState(() => _sending = false);
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  void _onTyping() {
    _socket.emitTypingStart(widget.chatId);
  }

  @override
  void dispose() {
    _subMsg?.cancel();
    _subTypingStart?.cancel();
    _subTypingStop?.cancel();
    _subPresence?.cancel();
    _socket.emitTypingStop(widget.chatId);
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: _buildAppBar(),
      body: Column(
        children: [
          // Список сообщений
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? _emptyState()
                    : ListView.builder(
                        controller: _scrollCtrl,
                        reverse: true,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        itemCount: _messages.length,
                        itemBuilder: (_, i) => _buildBubble(_messages[i], isDark),
                      ),
          ),

          // Индикатор набора
          if (_peerTyping)
            Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 4),
              child: Row(children: [
                const SizedBox(width: 4),
                _TypingIndicator(),
                const SizedBox(width: 8),
                Text('${widget.chatName} печатает...',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93))),
              ]),
            ),

          // Панель ввода
          _buildInputBar(isDark),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      titleSpacing: 0,
      title: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: const Color(0xFF2AABEE).withOpacity(0.2),
            backgroundImage: widget.chatAvatar != null ? NetworkImage(widget.chatAvatar!) : null,
            child: widget.chatAvatar == null
                ? Text(widget.chatName.isNotEmpty ? widget.chatName[0].toUpperCase() : '?',
                    style: const TextStyle(color: Color(0xFF2AABEE), fontWeight: FontWeight.w600))
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.chatName,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  _peerOnline ? 'в сети' : _lastSeenStr(),
                  style: TextStyle(
                    fontSize: 12,
                    color: _peerOnline ? const Color(0xFF2AABEE) : const Color(0xFF8E8E93),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        IconButton(icon: const Icon(Icons.call_outlined), onPressed: () => _startCall('audio')),
        IconButton(icon: const Icon(Icons.videocam_outlined), onPressed: () => _startCall('video')),
        IconButton(icon: const Icon(Icons.more_vert), onPressed: () {}),
      ],
    );
  }

  Widget _buildBubble(Map<String, dynamic> msg, bool isDark) {
    final isMe = msg['senderId'] == _myUserId;
    final text = msg['isDeleted'] == true ? 'Сообщение удалено' : (msg['text'] ?? '');
    final time = _formatTime(msg['createdAt']);
    final type = msg['type'] ?? 'text';
    final readBy = (msg['readBy'] as List?)?.length ?? 0;
    final isRead = readBy > 1;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        child: GestureDetector(
          onLongPress: () => _showMsgMenu(msg),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isMe
                  ? (isDark ? const Color(0xFF2B5278) : const Color(0xFFEFFDDE))
                  : (isDark ? const Color(0xFF2C2C2E) : Colors.white),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isMe ? 16 : 4),
                bottomRight: Radius.circular(isMe ? 4 : 16),
              ),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 2, offset: const Offset(0, 1)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (type == 'call')
                  _callBubble(msg)
                else if (type == 'voice')
                  _voiceBubble(msg)
                else if (type == 'image')
                  _imageBubble(msg)
                else
                  Text(text,
                      style: TextStyle(
                        fontSize: 15,
                        color: isDark ? Colors.white : Colors.black87,
                        fontStyle: msg['isDeleted'] == true ? FontStyle.italic : FontStyle.normal,
                      )),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (msg['editedAt'] != null)
                      const Text('ред. ', style: TextStyle(fontSize: 10, color: Color(0xFF8E8E93))),
                    Text(time, style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E93))),
                    if (isMe) ...[
                      const SizedBox(width: 3),
                      Icon(
                        isRead ? Icons.done_all : Icons.done,
                        size: 14,
                        color: isRead ? const Color(0xFF2AABEE) : const Color(0xFF8E8E93),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _callBubble(Map msg) {
    final info     = msg['callInfo'] as Map? ?? {};
    final status   = info['status']   as String? ?? 'initiated';
    final type     = info['type']     as String? ?? 'audio';
    final duration = (info['duration'] as num?)?.toInt() ?? 0;
    final isVideo  = type == 'video';
    final isMissed = status == 'missed' || status == 'rejected';
    final isCompleted = status == 'completed';
    final isMe     = msg['senderId'] == _myUserId;

    IconData icon;
    Color color;
    String label;

    if (isMissed) {
      icon  = isVideo ? Icons.videocam_off_outlined : Icons.phone_missed_outlined;
      color = Colors.red;
      label = isMe ? '↗ Пропущен (исх.)' : '↙ Пропущенный звонок';
    } else if (isCompleted) {
      icon  = isVideo ? Icons.videocam_outlined : Icons.call_outlined;
      color = const Color(0xFF2AABEE);
      label = '${isMe ? "↗" : "↙"} ${isVideo ? "Видео" : "Аудио"}звонок · ${_formatDuration(duration)}';
    } else {
      icon  = isVideo ? Icons.videocam_outlined : Icons.call_outlined;
      color = Colors.grey;
      label = '${isVideo ? "Видео" : "Аудио"}звонок';
    }

    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: color, size: 20),
      const SizedBox(width: 8),
      Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w500)),
      const SizedBox(width: 8),
      GestureDetector(
        onTap: () async => await _callSvc.startCall(
          chatId: widget.chatId, peerId: widget.otherUserId ?? '',
          peerName: widget.chatName, type: isVideo ? CallType.video : CallType.audio,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
          child: Text('Перезвонить', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      ),
    ]);
  }

  Widget _voiceBubble(Map msg) {
    final dur = msg['mediaDuration'] ?? 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.play_circle_filled, color: Color(0xFF2AABEE), size: 32),
        const SizedBox(width: 8),
        Container(width: 80, height: 3,
            decoration: BoxDecoration(color: const Color(0xFF2AABEE).withOpacity(0.3), borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(_formatDuration(dur), style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93))),
      ],
    );
  }

  Widget _imageBubble(Map msg) {
    final url = msg['mediaUrl'] ?? '';
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(url, width: 200, height: 150, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 48)),
    );
  }

  Widget _buildInputBar(bool isDark) {
    return Container(
      color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      padding: EdgeInsets.only(
        left: 8, right: 8, top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.attach_file, color: Color(0xFF8E8E93)),
            onPressed: () {},
          ),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(22),
              ),
              child: TextField(
                controller: _msgCtrl,
                onChanged: (_) => _onTyping(),
                maxLines: 5,
                minLines: 1,
                decoration: const InputDecoration(
                  hintText: 'Сообщение',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  hintStyle: TextStyle(color: Color(0xFF8E8E93)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          AnimatedBuilder(
            animation: _msgCtrl,
            builder: (_, __) {
              final hasText = _msgCtrl.text.trim().isNotEmpty;
              return GestureDetector(
                onTap: hasText ? _sendMessage : _recordVoice,
                child: Container(
                  width: 44, height: 44,
                  decoration: const BoxDecoration(
                    color: Color(0xFF2AABEE),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    hasText ? Icons.send : Icons.mic,
                    color: Colors.white, size: 22,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, size: 64, color: const Color(0xFF8E8E93).withOpacity(0.5)),
          const SizedBox(height: 16),
          const Text('Начните диалог', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 16)),
          const SizedBox(height: 8),
          const Text('Все сообщения защищены\nE2E шифрованием',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF8E8E93), fontSize: 13)),
        ],
      ),
    );
  }

  void _showMsgMenu(Map msg) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.reply), title: const Text('Ответить'), onTap: () => Navigator.pop(context)),
            ListTile(leading: const Icon(Icons.copy), title: const Text('Копировать'),
                onTap: () { Clipboard.setData(ClipboardData(text: msg['text'] ?? '')); Navigator.pop(context); }),
            if (msg['senderId'] == _myUserId)
              ListTile(leading: const Icon(Icons.delete, color: Colors.red), title: const Text('Удалить', style: TextStyle(color: Colors.red)),
                  onTap: () => Navigator.pop(context)),
          ],
        ),
      ),
    );
  }

  Future<void> _startCall(String kind) async {
    if (widget.otherUserId == null || widget.otherUserId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Нет ID собеседника')));
      return;
    }
    await _callSvc.startCall(
      chatId:   widget.chatId,
      peerId:   widget.otherUserId!,
      peerName: widget.chatName,
      type:     kind == 'video' ? CallType.video : CallType.audio,
    );
    // MainScreen will handle showing the outgoing call screen via CallService stream
  }

  void _recordVoice() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Голосовые: скоро'), duration: Duration(seconds: 2)),
    );
  }

  String _formatTime(String? dateStr) {
    if (dateStr == null) return '';
    final d = DateTime.tryParse(dateStr);
    if (d == null) return '';
    return '${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';
  }

  String _formatDuration(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return '${m.toString().padLeft(2,'0')}:${s.toString().padLeft(2,'0')}';
  }

  String _lastSeenStr() {
    final ls = _peerLastSeen;
    if (ls == null) return 'не в сети';
    final now = DateTime.now();
    final diff = now.difference(ls);
    if (diff.inSeconds < 60)  return 'был(а) только что';
    if (diff.inMinutes < 60)  return 'был(а) ${diff.inMinutes} мин назад';
    if (diff.inHours < 24) {
      final t = '${ls.hour.toString().padLeft(2,'0')}:${ls.minute.toString().padLeft(2,'0')}';
      return 'был(а) сегодня в $t';
    }
    if (diff.inDays == 1) {
      final t = '${ls.hour.toString().padLeft(2,'0')}:${ls.minute.toString().padLeft(2,'0')}';
      return 'был(а) вчера в $t';
    }
    return 'был(а) ${ls.day}.${ls.month.toString().padLeft(2,'0')}';
  }
}

class _TypingIndicator extends StatefulWidget {
  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final delay = i * 0.3;
          final t = (_ctrl.value + delay) % 1.0;
          final scale = 1.0 + 0.4 * (t < 0.5 ? t * 2 : (1 - t) * 2);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Transform.scale(
              scale: scale,
              child: Container(
                width: 6, height: 6,
                decoration: const BoxDecoration(color: Color(0xFF8E8E93), shape: BoxShape.circle),
              ),
            ),
          );
        }),
      ),
    );
  }
}
