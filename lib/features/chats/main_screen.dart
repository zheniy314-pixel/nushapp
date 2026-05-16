import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../core/services/socket_service.dart';
import '../../core/services/call_service.dart';
import '../chats/chats_list_screen.dart';
import '../contacts/contacts_screen.dart';
import '../mail/mail_screen.dart';
import '../channels/channels_screen.dart';
import '../settings/settings_screen.dart';
import 'chat_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  final _socket   = SocketService();
  final _callSvc  = CallService();
  final _storage  = const FlutterSecureStorage();
  final _notif    = FlutterLocalNotificationsPlugin();

  int _currentIndex = 0;
  // unread badge per tab
  int _chatsBadge = 0;

  StreamSubscription? _subPresence;
  StreamSubscription? _subMessage;
  StreamSubscription? _subCall;

  static const List<Widget> _screens = [
    ChatsListScreen(), ContactsScreen(), MailScreen(),
    ChannelsScreen(), SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    // Connect Socket.IO
    await _socket.connect();
    _callSvc.init();

    // Init local notifications
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit     = DarwinInitializationSettings();
    await _notif.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (_) {
        setState(() => _currentIndex = 0);
      },
    );

    // Subscribe to Socket events
    _subPresence = _socket.onPresenceUpdate.listen(_onPresence);
    _subMessage  = _socket.onMessageNew.listen(_onMessage);
    _subCall     = _callSvc.onSessionChange.listen(_onCallSession);
  }

  void _onPresence(Map<String, dynamic> data) {
    // Trigger chat list refresh via key or setState
    setState(() {});
  }

  void _onMessage(Map<String, dynamic> data) {
    // Show notification when not in that chat
    final chatId  = data['chatId'] as String? ?? '';
    final text    = data['text']   as String? ?? 'Новое сообщение';
    final sender  = data['senderName'] as String? ?? 'Нуша';

    if (_currentIndex != 0) {
      setState(() => _chatsBadge++);
    }

    // Disguised notification — looks like YouTube/Telegram/other app
    _showDisguisedNotification(sender, text, chatId);
  }

  // Notifications disguised as other popular apps
  static const _disguises = [
    ('YouTube', 'Новое видео', '@mipmap/ic_launcher'),
    ('WhatsApp', 'Сообщение', '@mipmap/ic_launcher'),
    ('Telegram', 'Уведомление', '@mipmap/ic_launcher'),
    ('Gmail', 'Новое письмо', '@mipmap/ic_launcher'),
    ('LinkedIn', 'Активность', '@mipmap/ic_launcher'),
  ];

  int _disguiseIdx = 0;

  Future<void> _showDisguisedNotification(String sender, String text, String chatId) async {
    final d = _disguises[_disguiseIdx % _disguises.length];
    _disguiseIdx++;

    const androidDetails = AndroidNotificationDetails(
      'nusha_masked', 'Notifications',
      channelDescription: 'App notifications',
      importance: Importance.high, priority: Priority.high,
      ticker: 'msg',
    );
    const iosDetails = DarwinNotificationDetails(presentBadge: true, presentSound: true);

    await _notif.show(
      DateTime.now().millisecondsSinceEpoch % 100000,
      d.$1,                    // disguised app name
      '$sender: $text',
      const NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  }

  void _onCallSession(CallSession? session) {
    if (!mounted) return;
    if (session == null) {
      // Call ended — pop call screen if open
      Navigator.of(context).popUntil((r) => r.isFirst || r.settings.name == '/main');
      return;
    }
    if (session.state == CallState.incoming) {
      _showIncomingCall(session);
    } else if (session.state == CallState.outgoing) {
      _showOutgoingCall(session);
    }
  }

  void _showIncomingCall(CallSession session) {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      pageBuilder: (ctx, anim, _) => _IncomingCallScreen(
        session: session,
        onAnswer: () async {
          Navigator.pop(ctx);
          await _callSvc.answerCall();
          if (mounted) _showActiveCall(session);
        },
        onReject: () async {
          Navigator.pop(ctx);
          await _callSvc.rejectCall();
        },
      ),
    );
  }

  void _showOutgoingCall(CallSession session) {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      pageBuilder: (ctx, anim, _) => _ActiveCallScreen(
        session: session,
        isOutgoing: true,
        onEnd: () async {
          Navigator.pop(ctx);
          await _callSvc.endCall();
        },
      ),
    );
  }

  void _showActiveCall(CallSession session) {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      pageBuilder: (ctx, anim, _) => _ActiveCallScreen(
        session: session,
        isOutgoing: false,
        onEnd: () async {
          Navigator.pop(ctx);
          await _callSvc.endCall();
        },
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _socket.connect();
    }
    if (state == AppLifecycleState.paused) {
      // Keep socket alive for background notifications
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subPresence?.cancel();
    _subMessage?.cancel();
    _subCall?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    return BottomNavigationBar(
      currentIndex: _currentIndex,
      onTap: (i) {
        setState(() {
          _currentIndex = i;
          if (i == 0) _chatsBadge = 0;
        });
      },
      items: [
        BottomNavigationBarItem(
          icon: _badge(Icons.chat_bubble_outline, _chatsBadge),
          activeIcon: const Icon(Icons.chat_bubble),
          label: 'Чаты',
        ),
        const BottomNavigationBarItem(icon: Icon(Icons.people_outline), activeIcon: Icon(Icons.people), label: 'Контакты'),
        const BottomNavigationBarItem(icon: Icon(Icons.mail_outline),   activeIcon: Icon(Icons.mail),   label: 'Почта'),
        const BottomNavigationBarItem(icon: Icon(Icons.campaign_outlined), activeIcon: Icon(Icons.campaign), label: 'Каналы'),
        const BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), activeIcon: Icon(Icons.settings), label: 'Настройки'),
      ],
    );
  }

  Widget _badge(IconData icon, int count) {
    if (count == 0) return Icon(icon);
    return Stack(clipBehavior: Clip.none, children: [
      Icon(icon),
      Positioned(right: -6, top: -4,
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: const BoxDecoration(color: Color(0xFF2AABEE), shape: BoxShape.circle),
          child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
        )),
    ]);
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// INCOMING CALL SCREEN
// ──────────────────────────────────────────────────────────────────────────────
class _IncomingCallScreen extends StatefulWidget {
  final CallSession session;
  final VoidCallback onAnswer;
  final VoidCallback onReject;
  const _IncomingCallScreen({required this.session, required this.onAnswer, required this.onReject});
  @override State<_IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<_IncomingCallScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulse;

  @override void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);
  }
  @override void dispose() { _pulse.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext ctx) {
    final isVideo = widget.session.type == CallType.video;
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [const Color(0xFF1A1D2E), isVideo ? Colors.teal.shade900 : Colors.indigo.shade900],
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(children: [
            const SizedBox(height: 40),
            Text(isVideo ? '📹 Входящий видеозвонок' : '📞 Входящий звонок',
                style: const TextStyle(color: Colors.white70, fontSize: 16)),
            const SizedBox(height: 30),
            AnimatedBuilder(
              animation: _pulse,
              builder: (_, __) => Container(
                width: 100 + _pulse.value * 10,
                height: 100 + _pulse.value * 10,
                decoration: BoxDecoration(
                  color: const Color(0xFF2AABEE).withOpacity(0.3),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: CircleAvatar(
                    radius: 44,
                    backgroundColor: const Color(0xFF2AABEE),
                    child: Text(
                      widget.session.peerName.isNotEmpty ? widget.session.peerName[0].toUpperCase() : '?',
                      style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(widget.session.peerName,
                style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text('Вызывает...', style: TextStyle(color: Colors.white54, fontSize: 16)),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                // Reject
                Column(children: [
                  GestureDetector(
                    onTap: widget.onReject,
                    child: Container(
                      width: 72, height: 72,
                      decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                      child: const Icon(Icons.call_end, color: Colors.white, size: 32),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text('Отклонить', style: TextStyle(color: Colors.white70)),
                ]),
                // Answer
                Column(children: [
                  GestureDetector(
                    onTap: widget.onAnswer,
                    child: Container(
                      width: 72, height: 72,
                      decoration: BoxDecoration(color: Colors.green.shade600, shape: BoxShape.circle),
                      child: Icon(isVideo ? Icons.videocam : Icons.call, color: Colors.white, size: 32),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text('Ответить', style: TextStyle(color: Colors.white70)),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// ACTIVE CALL SCREEN (outgoing + connected)
// ──────────────────────────────────────────────────────────────────────────────
class _ActiveCallScreen extends StatefulWidget {
  final CallSession session;
  final bool isOutgoing;
  final VoidCallback onEnd;
  const _ActiveCallScreen({required this.session, required this.isOutgoing, required this.onEnd});
  @override State<_ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends State<_ActiveCallScreen> {
  bool _micMuted  = false;
  bool _speakerOn = false;
  bool _camOff    = false;
  int  _seconds   = 0;
  Timer? _uiTimer;
  StreamSubscription? _subSession;

  // WebRTC video renderers
  final _localRenderer  = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  bool _renderersReady  = false;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  @override
  void initState() {
    super.initState();
    _initRenderers();

    // Listen for session changes (active state + stream updates)
    _subSession = CallService().onSessionChange.listen((s) {
      if (!mounted) return;
      if (s == null) { widget.onEnd(); return; }
      if (s.state == CallState.active && _uiTimer == null) _startUiTimer();
      if (s.localStream != null && s.localStream != _localStream) {
        _localStream = s.localStream;
        setState(() => _localRenderer.srcObject = _localStream);
      }
      if (s.remoteStream != null && s.remoteStream != _remoteStream) {
        _remoteStream = s.remoteStream;
        setState(() => _remoteRenderer.srcObject = _remoteStream);
      }
    });

    // Also check current session for existing streams
    final cur = CallService().current;
    if (cur?.localStream != null)  { _localStream  = cur!.localStream;  }
    if (cur?.remoteStream != null) { _remoteStream = cur!.remoteStream; }
    if (cur?.state == CallState.active) _startUiTimer();
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    if (mounted) {
      setState(() {
        _renderersReady = true;
        if (_localStream  != null) _localRenderer.srcObject  = _localStream;
        if (_remoteStream != null) _remoteRenderer.srcObject = _remoteStream;
      });
    }
  }

  void _startUiTimer() {
    _uiTimer?.cancel();
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds = CallService().durationSec);
    });
  }

  String get _timeStr {
    final m = (_seconds ~/ 60).toString().padLeft(2, '0');
    final s = (_seconds %  60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  bool get _isActive => CallService().current?.state == CallState.active;

  void _toggleMic() {
    final stream = CallService().current?.localStream;
    stream?.getAudioTracks().forEach((t) => t.enabled = _micMuted);
    setState(() => _micMuted = !_micMuted);
  }

  void _toggleCam() {
    final stream = CallService().current?.localStream;
    stream?.getVideoTracks().forEach((t) => t.enabled = _camOff);
    setState(() => _camOff = !_camOff);
  }

  @override
  Widget build(BuildContext ctx) {
    final isVideo = widget.session.type == CallType.video;
    final hasRemote = _remoteStream != null && _renderersReady;
    final hasLocal  = _localStream  != null && _renderersReady;

    if (isVideo && hasRemote) {
      // ── Full-screen video layout ──────────────────────────────────────
      return Material(
        color: Colors.black,
        child: Stack(fit: StackFit.expand, children: [
          // Remote video (full screen)
          RTCVideoView(_remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),

          // Local video (small preview top-right)
          if (hasLocal)
            Positioned(top: 56, right: 16, width: 100, height: 140,
              child: ClipRRect(borderRadius: BorderRadius.circular(12),
                child: RTCVideoView(_localRenderer, mirror: true,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover))),

          // Timer + name overlay (top)
          Positioned(top: 0, left: 0, right: 0,
            child: SafeArea(child: Padding(padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.session.peerName,
                    style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700,
                        shadows: [Shadow(blurRadius: 8)])),
                Text(_isActive ? '🟢 $_timeStr' : '📡 Соединение...',
                    style: const TextStyle(color: Colors.white70, fontSize: 14)),
              ])))),

          // Control bar (bottom)
          Positioned(bottom: 0, left: 0, right: 0,
            child: SafeArea(child: _buildControls(isVideo: true))),
        ]),
      );
    }

    // ── Audio call layout (or video without stream yet) ─────────────────
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [const Color(0xFF0D1117), isVideo ? Colors.teal.shade900 : const Color(0xFF1A1D2E)],
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(child: Column(children: [
          const SizedBox(height: 28),
          // Status chip
          _statusChip(),
          const SizedBox(height: 40),
          // Avatar (or local camera if video)
          isVideo && hasLocal
              ? SizedBox(width: 160, height: 200,
                  child: ClipRRect(borderRadius: BorderRadius.circular(16),
                    child: RTCVideoView(_localRenderer, mirror: true,
                        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)))
              : CircleAvatar(radius: 56, backgroundColor: const Color(0xFF2AABEE),
                  child: Text(widget.session.peerName.isNotEmpty
                      ? widget.session.peerName[0].toUpperCase() : '?',
                      style: const TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.w700))),
          const SizedBox(height: 20),
          Text(widget.session.peerName,
              style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(isVideo ? '📹 Видеозвонок' : '📞 Аудиозвонок',
              style: const TextStyle(color: Colors.white54, fontSize: 15)),
          const Spacer(),
          _buildControls(isVideo: isVideo),
        ])),
      ),
    );
  }

  Widget _statusChip() {
    final connected = _isActive;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: connected ? Colors.green.withOpacity(0.2) : Colors.orange.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: connected ? Colors.green : Colors.orange),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8, margin: const EdgeInsets.only(right: 6),
          decoration: BoxDecoration(color: connected ? Colors.green : Colors.orange, shape: BoxShape.circle)),
        Text(connected ? '🟢 $_timeStr' : (widget.isOutgoing ? 'Вызов...' : 'Соединение...'),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _buildControls({required bool isVideo}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _ctrlBtn(_micMuted ? Icons.mic_off : Icons.mic,
              _micMuted ? Colors.white24 : Colors.white12, 'Микр.', _toggleMic),
          if (isVideo)
            _ctrlBtn(_camOff ? Icons.videocam_off : Icons.videocam,
                _camOff ? Colors.white24 : Colors.white12, 'Камера', _toggleCam),
          _ctrlBtn(Icons.volume_up, _speakerOn ? const Color(0xFF2AABEE).withOpacity(0.4) : Colors.white12,
              'Динамик', () => setState(() => _speakerOn = !_speakerOn)),
        ]),
        const SizedBox(height: 24),
        GestureDetector(
          onTap: widget.onEnd,
          child: Container(
            width: 72, height: 72, margin: const EdgeInsets.only(bottom: 16),
            decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
            child: const Icon(Icons.call_end, color: Colors.white, size: 32),
          ),
        ),
      ]),
    );
  }

  Widget _ctrlBtn(IconData icon, Color bg, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(children: [
        Container(width: 56, height: 56,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle, border: Border.all(color: Colors.white24)),
          child: Icon(icon, color: Colors.white)),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
      ]),
    );
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    _subSession?.cancel();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }
}
