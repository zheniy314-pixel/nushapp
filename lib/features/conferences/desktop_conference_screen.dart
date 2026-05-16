import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../core/api/api_service.dart';
import '../../core/services/socket_service.dart';
import 'dart:async';

/// Десктопный экран конференции — до 50 участников с видео
/// Используется на Windows и Linux
class DesktopConferenceScreen extends StatefulWidget {
  final String roomCode;
  final String title;
  final bool isHost;

  const DesktopConferenceScreen({
    super.key,
    required this.roomCode,
    required this.title,
    this.isHost = false,
  });

  @override
  State<DesktopConferenceScreen> createState() => _DesktopConferenceScreenState();
}

class _DesktopConferenceScreenState extends State<DesktopConferenceScreen> {
  final _api    = ApiService();
  final _socket = SocketService();

  final _localRenderer = RTCVideoRenderer();
  final Map<String, RTCVideoRenderer> _remoteRenderers = {};
  final Map<String, RTCPeerConnection> _peers = {};
  MediaStream? _localStream;

  List<Map<String, dynamic>> _participants = [];
  String? _activeSpeakerId;
  bool _audioMuted = false;
  bool _videoMuted = false;
  bool _handRaised = false;
  bool _chatOpen = true;
  bool _participantsOpen = true;
  int _elapsed = 0;
  final _chatMessages = <Map<String, dynamic>>[];
  final _chatCtrl = TextEditingController();

  late final List<StreamSubscription> _subs;

  @override
  void initState() {
    super.initState();
    _init();
    Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed++);
    });
  }

  Future<void> _init() async {
    await _localRenderer.initialize();
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true, 'video': {'width': 1280, 'height': 720},
    });
    _localRenderer.srcObject = _localStream;

    _subs = [
      _socket.onConfSignal.listen(_handleSignal),
      _socket.onConfIce.listen(_handleIce),
    ];

    await _loadConference();
  }

  Future<void> _loadConference() async {
    try {
      final r = await _api.dio.get('/conferences/${widget.roomCode}/state');
      final conf = r.data['conference'] as Map<String, dynamic>;
      setState(() => _participants = List<Map<String, dynamic>>.from(conf['participants'] ?? []));
      for (final p in _participants) {
        final uid = p['userId'] as String;
        await _createPeer(uid, initiator: true);
      }
    } catch (_) {}
  }

  Future<RTCPeerConnection> _createPeer(String peerId, {bool initiator = false}) async {
    final iceServers = await _api.getTurnCredentials();
    final pc = await createPeerConnection({'iceServers': iceServers});
    _peers[peerId] = pc;

    final renderer = RTCVideoRenderer();
    await renderer.initialize();
    _remoteRenderers[peerId] = renderer;

    _localStream?.getTracks().forEach((t) => pc.addTrack(t, _localStream!));

    pc.onTrack = (e) {
      if (e.streams.isNotEmpty) {
        setState(() {
          _remoteRenderers[peerId]?.srcObject = e.streams[0];
          _activeSpeakerId ??= peerId;
        });
      }
    };

    pc.onIceCandidate = (c) {
      if (c.candidate != null) {
        _socket.emitConfIce(widget.roomCode, peerId,
            {'candidate': c.candidate, 'sdpMid': c.sdpMid, 'sdpMLineIndex': c.sdpMLineIndex});
      }
    };

    if (initiator) {
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      _socket.emitConfSignal(widget.roomCode, peerId, {'type': 'offer', 'sdp': offer.sdp});
    }
    return pc;
  }

  Future<void> _handleSignal(Map<String, dynamic> d) async {
    final from = d['from'] as String;
    final data = d['data'] as Map<String, dynamic>;
    final type = data['type'] as String?;

    if (type == 'offer') {
      final pc = await _createPeer(from, initiator: false);
      await pc.setRemoteDescription(RTCSessionDescription(data['sdp'], 'offer'));
      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      _socket.emitConfSignal(widget.roomCode, from, {'type': 'answer', 'sdp': answer.sdp});
    } else if (type == 'answer') {
      await _peers[from]?.setRemoteDescription(RTCSessionDescription(data['sdp'], 'answer'));
    }
  }

  Future<void> _handleIce(Map<String, dynamic> d) async {
    final from = d['from'] as String;
    final c = d['candidate'] as Map<String, dynamic>?;
    if (c == null) return;
    await _peers[from]?.addCandidate(RTCIceCandidate(c['candidate'], c['sdpMid'], c['sdpMLineIndex']));
  }

  Future<void> _leave() async {
    await _api.leaveConference(widget.roomCode);
    _localStream?.dispose();
    for (final pc in _peers.values) pc.close();
    for (final r in _remoteRenderers.values) r.dispose();
    await _localRenderer.dispose();
    if (mounted) Navigator.of(context).pop();
  }

  String get _elapsedStr {
    final h = _elapsed ~/ 3600;
    final m = (_elapsed % 3600) ~/ 60;
    final s = _elapsed % 60;
    return h > 0
        ? '${h.toString().padLeft(2,'0')}:${m.toString().padLeft(2,'0')}:${s.toString().padLeft(2,'0')}'
        : '${m.toString().padLeft(2,'0')}:${s.toString().padLeft(2,'0')}';
  }

  @override
  void dispose() {
    for (final s in _subs) s.cancel();
    _chatCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1C1C1E),
      body: Column(
        children: [
          // Верхняя панель
          _buildTopBar(),

          // Основная область
          Expanded(
            child: Row(
              children: [
                // Видео-сетка (главная область)
                Expanded(child: _buildVideoArea()),

                // Правая панель: участники + чат
                if (_participantsOpen || _chatOpen)
                  _buildRightPanel(),
              ],
            ),
          ),

          // Лента миниатюр
          _buildThumbnailStrip(),

          // Нижняя панель управления
          _buildControls(),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      height: 56,
      color: const Color(0xFF2C2C2E),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                Text('$_elapsedStr · ${_participants.length + 1} участников',
                    style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 11)),
              ],
            ),
          ),
          // Кнопки панелей
          _iconToggle(Icons.people_outline, 'Участники', _participantsOpen,
              () => setState(() => _participantsOpen = !_participantsOpen)),
          const SizedBox(width: 8),
          _iconToggle(Icons.chat_bubble_outline, 'Чат', _chatOpen,
              () => setState(() => _chatOpen = !_chatOpen)),
          const SizedBox(width: 16),
          if (widget.isHost)
            TextButton(
              onPressed: () async {
                await _api.dio.post('/conferences/${widget.roomCode}/end');
                await _leave();
              },
              child: const Text('Завершить', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }

  Widget _iconToggle(IconData icon, String tooltip, bool active, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, color: active ? const Color(0xFF2AABEE) : const Color(0xFF8E8E93)),
        onPressed: onTap,
      ),
    );
  }

  Widget _buildVideoArea() {
    // Активный спикер — большое видео
    final activePeerId = _activeSpeakerId;
    return Container(
      color: Colors.black,
      child: activePeerId != null && _remoteRenderers.containsKey(activePeerId)
          ? Stack(fit: StackFit.expand, children: [
              RTCVideoView(_remoteRenderers[activePeerId]!,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain),
              Positioned(bottom: 12, left: 12,
                  child: _participantLabel(activePeerId)),
            ])
          : const Center(child: Icon(Icons.person, size: 120, color: Color(0xFF3A3A3C))),
    );
  }

  Widget _buildThumbnailStrip() {
    final all = [
      {'id': 'local', 'renderer': _localRenderer, 'name': 'Вы'},
      for (final e in _remoteRenderers.entries)
        {'id': e.key, 'renderer': e.value, 'name': e.key.substring(0, 6)},
    ];
    if (all.length <= 1) return const SizedBox();

    return Container(
      height: 100,
      color: const Color(0xFF2C2C2E),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        itemCount: all.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final item = all[i];
          final isActive = item['id'] == _activeSpeakerId;
          return GestureDetector(
            onTap: () => setState(() => _activeSpeakerId = item['id'] as String),
            child: Container(
              width: 130,
              decoration: BoxDecoration(
                border: Border.all(color: isActive ? const Color(0xFF2AABEE) : Colors.transparent, width: 2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Stack(fit: StackFit.expand, children: [
                  RTCVideoView(item['renderer'] as RTCVideoRenderer,
                      mirror: item['id'] == 'local',
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
                  Positioned(bottom: 4, left: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                        child: Text(item['name'] as String,
                            style: const TextStyle(color: Colors.white, fontSize: 10)),
                      )),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRightPanel() {
    return Container(
      width: 280,
      color: const Color(0xFF2C2C2E),
      child: Column(
        children: [
          if (_participantsOpen) _buildParticipantsList(),
          if (_chatOpen) Expanded(child: _buildChat()),
        ],
      ),
    );
  }

  Widget _buildParticipantsList() {
    return Container(
      height: 200,
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFF38383A)))),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Align(alignment: Alignment.centerLeft,
                child: Text('Участники', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _participants.length + 1,
              itemBuilder: (_, i) {
                if (i == 0) return _participantTile('Вы', isLocal: true);
                final p = _participants[i - 1];
                return _participantTile(p['userId'] as String? ?? '?',
                    audioMuted: p['audioMuted'] == true, handRaised: p['handRaised'] == true);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _participantTile(String name, {bool isLocal = false, bool audioMuted = false, bool handRaised = false}) {
    return ListTile(
      dense: true,
      leading: CircleAvatar(radius: 16,
          backgroundColor: const Color(0xFF2AABEE).withOpacity(0.2),
          child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(color: Color(0xFF2AABEE), fontSize: 12))),
      title: Text(name, style: const TextStyle(color: Colors.white, fontSize: 13)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (handRaised) const Icon(Icons.pan_tool, color: Colors.orange, size: 14),
        if (audioMuted) const Icon(Icons.mic_off, color: Colors.red, size: 14),
      ]),
    );
  }

  Widget _buildChat() {
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(12),
          child: Align(alignment: Alignment.centerLeft,
              child: Text('Чат', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
        ),
        Expanded(
          child: ListView.builder(
            reverse: true,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: _chatMessages.length,
            itemBuilder: (_, i) {
              final m = _chatMessages[_chatMessages.length - 1 - i];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  CircleAvatar(radius: 12,
                      backgroundColor: const Color(0xFF2AABEE).withOpacity(0.2),
                      child: Text((m['name'] as String? ?? '?')[0].toUpperCase(),
                          style: const TextStyle(color: Color(0xFF2AABEE), fontSize: 10))),
                  const SizedBox(width: 8),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(m['name'] as String? ?? '?',
                        style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 11)),
                    Text(m['text'] as String? ?? '',
                        style: const TextStyle(color: Colors.white, fontSize: 13)),
                  ])),
                ]),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _chatCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Написать в чат...',
                  hintStyle: const TextStyle(color: Color(0xFF8E8E93)),
                  filled: true, fillColor: const Color(0xFF3A3A3C),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                onSubmitted: (_) => _sendChatMsg(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(icon: const Icon(Icons.send, color: Color(0xFF2AABEE)), onPressed: _sendChatMsg),
          ]),
        ),
      ],
    );
  }

  void _sendChatMsg() {
    final text = _chatCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _chatMessages.add({'name': 'Вы', 'text': text}));
    _chatCtrl.clear();
  }

  Widget _buildControls() {
    return Container(
      height: 72,
      color: const Color(0xFF2C2C2E),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Левые кнопки
          Row(children: [
            _ctrlBtn(_audioMuted ? Icons.mic_off : Icons.mic,
                _audioMuted ? Colors.red : const Color(0xFF2AABEE), 'Микрофон',
                () { final t = _localStream?.getAudioTracks(); t?.forEach((x) => x.enabled = _audioMuted); setState(() => _audioMuted = !_audioMuted); }),
            const SizedBox(width: 12),
            _ctrlBtn(_videoMuted ? Icons.videocam_off : Icons.videocam,
                _videoMuted ? Colors.red : const Color(0xFF2AABEE), 'Камера',
                () { final t = _localStream?.getVideoTracks(); t?.forEach((x) => x.enabled = _videoMuted); setState(() => _videoMuted = !_videoMuted); }),
            const SizedBox(width: 12),
            _ctrlBtn(Icons.screen_share_outlined, const Color(0xFF2AABEE), 'Экран', () {}),
          ]),

          // Центр
          Row(children: [
            _ctrlBtn(_handRaised ? Icons.pan_tool : Icons.pan_tool_outlined,
                _handRaised ? Colors.orange : const Color(0xFF8E8E93), 'Рука',
                () { setState(() => _handRaised = !_handRaised); _api.dio.patch('/conferences/${widget.roomCode}/media', data: {'handRaised': _handRaised}); }),
            const SizedBox(width: 12),
            _ctrlBtn(Icons.poll_outlined, const Color(0xFF8E8E93), 'Опрос', () {}),
            const SizedBox(width: 12),
            _ctrlBtn(Icons.more_horiz, const Color(0xFF8E8E93), 'Ещё', () {}),
          ]),

          // Правые кнопки
          ElevatedButton.icon(
            onPressed: _leave,
            icon: const Icon(Icons.call_end, size: 18),
            label: const Text('Покинуть'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              minimumSize: const Size(120, 44),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ctrlBtn(IconData icon, Color color, String label, VoidCallback onTap) {
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: color, fontSize: 10)),
          ]),
        ),
      ),
    );
  }

  Widget _participantLabel(String id) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
      child: Text(id.length > 8 ? id.substring(0, 8) : id,
          style: const TextStyle(color: Colors.white, fontSize: 12)),
    );
  }
}
