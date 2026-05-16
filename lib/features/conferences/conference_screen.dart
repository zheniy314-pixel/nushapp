import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/config/app_config.dart';
import '../../core/services/socket_service.dart';

class ConferenceScreen extends StatefulWidget {
  final String roomCode;
  final String title;
  final bool isHost;

  const ConferenceScreen({
    super.key,
    required this.roomCode,
    required this.title,
    this.isHost = false,
  });

  @override
  State<ConferenceScreen> createState() => _ConferenceScreenState();
}

class _ConferenceScreenState extends State<ConferenceScreen> {
  final _storage = const FlutterSecureStorage();
  final _dio     = Dio(BaseOptions(baseUrl: AppConfig.apiUrl));
  final _socket  = SocketService();

  // WebRTC
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderers = <String, RTCVideoRenderer>{};
  final _peers = <String, RTCPeerConnection>{};
  MediaStream? _localStream;

  List<Map<String, dynamic>> _participants = [];
  bool _audioMuted  = false;
  bool _videoMuted  = false;
  bool _handRaised  = false;
  bool _loading     = true;
  bool _hasPermissions = false;
  String? _myUserId;
  String? _myName;
  int _elapsed = 0;
  Timer? _timer;

  StreamSubscription? _subSignal;
  StreamSubscription? _subIce;

  static const _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ]
  };

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) { if (mounted) setState(() => _elapsed++); });
    _init();
  }

  Future<void> _init() async {
    final token = await _storage.read(key: 'access_token');
    _myUserId   = await _storage.read(key: 'user_id');
    _myName     = await _storage.read(key: 'user_name') ?? 'Вы';
    if (token != null) _dio.options.headers['Authorization'] = 'Bearer $token';

    await _localRenderer.initialize();

    // Subscribe to socket signals
    _subSignal = _socket.onConfSignal.listen(_onConfSignal);
    _subIce    = _socket.onConfIce.listen(_onConfIce);

    // Request permissions and get media
    await _initMedia();

    // Join conference on server
    await _joinConference();

    setState(() => _loading = false);
  }

  Future<void> _initMedia() async {
    try {
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': {'facingMode': 'user', 'width': 320, 'height': 240},
      });
      _localRenderer.srcObject = _localStream;
      setState(() => _hasPermissions = true);
    } catch (e) {
      // Video failed — try audio only
      try {
        _localStream = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': false});
        setState(() { _hasPermissions = true; _videoMuted = true; });
      } catch (_) {
        setState(() => _hasPermissions = false);
      }
    }
  }

  Future<void> _joinConference() async {
    try {
      final r = await _dio.post('/conferences/${widget.roomCode}/join');
      final conf = (r.data['conference'] ?? r.data) as Map<String, dynamic>;
      final parts = List<Map<String, dynamic>>.from(conf['participants'] ?? []);
      setState(() => _participants = parts);

      // Notify other participants that we joined (so they can start WebRTC with us)
      _socket.emitConfJoin(widget.roomCode, _myName ?? 'Участник');

      // Connect to existing participants (we are the initiator for them)
      for (final p in parts) {
        final uid = p['userId']?.toString() ?? '';
        if (uid.isNotEmpty && uid != _myUserId) {
          await _createPeer(uid, isInitiator: true);
        }
      }
    } catch (_) {
      // If join fails, still show the room
    }
  }

  void _onConfSignal(Map<String, dynamic> data) async {
    final from    = data['from']?.toString() ?? '';
    final roomCode = data['roomCode']?.toString() ?? '';
    if (roomCode != widget.roomCode && roomCode.isNotEmpty) return;
    final sdpData = data['data'] as Map<String, dynamic>? ?? {};
    final type    = sdpData['type'] as String? ?? '';

    if (type == 'offer') {
      await _handleOffer(from, sdpData);
    } else if (type == 'answer') {
      final pc = _peers[from];
      if (pc != null) {
        await pc.setRemoteDescription(RTCSessionDescription(sdpData['sdp'] as String, 'answer'));
      }
    } else if (type == 'join') {
      // New participant joined
      if (!_participants.any((p) => p['userId'] == from)) {
        setState(() => _participants.add({'userId': from, 'name': data['name'] ?? from}));
        await _createPeer(from, isInitiator: true);
      }
    } else if (type == 'leave') {
      _removePeer(from);
      setState(() => _participants.removeWhere((p) => p['userId'] == from));
    }
  }

  void _onConfIce(Map<String, dynamic> data) async {
    final from      = data['from']?.toString() ?? '';
    final candidate = data['candidate'] as Map<String, dynamic>? ?? {};
    final pc = _peers[from];
    if (pc != null && candidate['candidate'] != null) {
      try {
        await pc.addCandidate(RTCIceCandidate(
          candidate['candidate'] as String,
          candidate['sdpMid'] as String?,
          (candidate['sdpMLineIndex'] as num?)?.toInt(),
        ));
      } catch (_) {}
    }
  }

  Future<void> _handleOffer(String from, Map sdpData) async {
    final pc = await _createPeer(from, isInitiator: false);
    await pc.setRemoteDescription(RTCSessionDescription(sdpData['sdp'] as String, 'offer'));
    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    _socket.emitConfSignal(widget.roomCode, from, {'type': 'answer', 'sdp': answer.sdp});
  }

  Future<RTCPeerConnection> _createPeer(String peerId, {bool isInitiator = false}) async {
    if (_peers.containsKey(peerId)) return _peers[peerId]!;

    final pc = await createPeerConnection(_iceServers);
    _peers[peerId] = pc;

    final renderer = RTCVideoRenderer();
    await renderer.initialize();
    setState(() => _remoteRenderers[peerId] = renderer);

    _localStream?.getTracks().forEach((t) => pc.addTrack(t, _localStream!));

    pc.onTrack = (e) {
      if (e.streams.isNotEmpty && mounted) {
        setState(() => _remoteRenderers[peerId]?.srcObject = e.streams[0]);
      }
    };

    pc.onIceCandidate = (c) {
      if (c.candidate != null) {
        _socket.emitConfIce(widget.roomCode, peerId, {
          'candidate': c.candidate, 'sdpMid': c.sdpMid, 'sdpMLineIndex': c.sdpMLineIndex,
        });
      }
    };

    pc.onConnectionState = (s) {
      if ((s == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
           s == RTCPeerConnectionState.RTCPeerConnectionStateFailed) && mounted) {
        _removePeer(peerId);
      }
    };

    if (isInitiator) {
      final offer = await pc.createOffer({'offerToReceiveAudio': true, 'offerToReceiveVideo': true});
      await pc.setLocalDescription(offer);
      _socket.emitConfSignal(widget.roomCode, peerId, {'type': 'offer', 'sdp': offer.sdp, 'name': _myName});
    }

    return pc;
  }

  void _removePeer(String peerId) {
    _peers[peerId]?.close();
    _peers.remove(peerId);
    if (mounted) setState(() { _remoteRenderers[peerId]?.dispose(); _remoteRenderers.remove(peerId); });
  }

  Future<void> _toggleAudio() async {
    final tracks = _localStream?.getAudioTracks() ?? [];
    for (final t in tracks) t.enabled = _audioMuted;
    setState(() => _audioMuted = !_audioMuted);
  }

  Future<void> _toggleVideo() async {
    final tracks = _localStream?.getVideoTracks() ?? [];
    for (final t in tracks) t.enabled = _videoMuted;
    setState(() => _videoMuted = !_videoMuted);
  }

  Future<void> _leave() async {
    try {
      await _dio.post('/conferences/${widget.roomCode}/leave');
      _socket.emitConfSignal(widget.roomCode, '', {'type': 'leave'});
    } catch (_) {}
    _cleanup();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _endForAll() async {
    try { await _dio.post('/conferences/${widget.roomCode}/end'); } catch (_) {}
    _cleanup();
    if (mounted) Navigator.of(context).pop();
  }

  void _cleanup() {
    _timer?.cancel();
    _subSignal?.cancel();
    _subIce?.cancel();
    _localStream?.dispose();
    _localRenderer.dispose();
    for (final r in _remoteRenderers.values) r.dispose();
    for (final p in _peers.values) p.close();
  }

  String get _elapsedStr {
    final h = _elapsed ~/ 3600;
    final m = (_elapsed % 3600) ~/ 60;
    final s = _elapsed % 60;
    if (h > 0) return '${h.toString().padLeft(2,'0')}:${m.toString().padLeft(2,'0')}:${s.toString().padLeft(2,'0')}';
    return '${m.toString().padLeft(2,'0')}:${s.toString().padLeft(2,'0')}';
  }

  String _peerName(String userId) {
    final p = _participants.firstWhere((p) => p['userId'] == userId, orElse: () => {});
    return (p['name'] ?? p['displayName'] ?? userId.substring(0, 6)) as String;
  }

  @override
  Widget build(BuildContext ctx) {
    if (_loading) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const CircularProgressIndicator(color: Color(0xFF2AABEE)),
          const SizedBox(height: 16),
          Text('Подключаемся к ${widget.roomCode}...', style: const TextStyle(color: Colors.white70)),
        ])),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _buildAppBar(),
      body: Column(children: [
        // Код комнаты
        _roomCodeBanner(),
        // Основная область
        Expanded(child: _hasPermissions ? _buildVideoGrid() : _noPermissions()),
        // Панель управления
        _buildControls(),
      ]),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF0D1117),
      foregroundColor: Colors.white,
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
        Text('$_elapsedStr · ${_participants.length + 1} участников',
            style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E93))),
      ]),
      actions: [
        if (widget.isHost)
          TextButton(
            onPressed: _endForAll,
            child: const Text('Завершить', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
          )
        else
          TextButton(onPressed: _leave, child: const Text('Выйти', style: TextStyle(color: Colors.orange))),
      ],
    );
  }

  Widget _roomCodeBanner() {
    return GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: widget.roomCode));
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Код скопирован')));
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        color: const Color(0xFF1A1D2E),
        child: Row(children: [
          const Icon(Icons.meeting_room_outlined, color: Color(0xFF2AABEE), size: 16),
          const SizedBox(width: 8),
          Text('Код: ${widget.roomCode}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, letterSpacing: 1)),
          const SizedBox(width: 8),
          const Icon(Icons.copy, color: Color(0xFF8E8E93), size: 14),
          const Spacer(),
          Text('${_participants.length + 1} чел.', style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 12)),
        ]),
      ),
    );
  }

  Widget _noPermissions() {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.mic_off, color: Colors.red, size: 64),
      const SizedBox(height: 16),
      const Text('Нет разрешений на камеру/микрофон', style: TextStyle(color: Colors.white, fontSize: 16)),
      const SizedBox(height: 8),
      const Text('Разрешите доступ в настройках устройства', style: TextStyle(color: Color(0xFF8E8E93))),
      const SizedBox(height: 24),
      ElevatedButton.icon(
        icon: const Icon(Icons.refresh),
        label: const Text('Повторить'),
        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2AABEE)),
        onPressed: () async { await _initMedia(); if (mounted) setState(() {}); },
      ),
      // Audio-only mode
      const SizedBox(height: 12),
      _buildAudioOnlyParticipantList(),
    ]));
  }

  Widget _buildAudioOnlyParticipantList() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFF1A1D2E), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Участники конференции', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        _participantRow(_myName ?? 'Вы', isMe: true, online: true),
        ..._participants.map((p) => _participantRow(
          p['name'] ?? p['userId']?.toString().substring(0, 6) ?? '?',
          isMe: false, online: true,
        )),
      ]),
    );
  }

  Widget _participantRow(String name, {bool isMe = false, bool online = true}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        CircleAvatar(radius: 18, backgroundColor: isMe ? const Color(0xFF2AABEE) : Colors.deepPurple.withOpacity(0.6),
          child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
        const SizedBox(width: 12),
        Text(isMe ? '$name (Вы)' : name, style: const TextStyle(color: Colors.white)),
        const Spacer(),
        if (online) const Icon(Icons.mic, color: Colors.green, size: 16)
        else const Icon(Icons.mic_off, color: Colors.red, size: 16),
      ]),
    );
  }

  Widget _buildVideoGrid() {
    // All participants: me + remote
    final allIds = ['__me__', ..._remoteRenderers.keys];
    final count  = allIds.length;

    if (count == 1) {
      return _videoTile('__me__', isMe: true);
    }
    if (count == 2) {
      return Column(children: [
        Expanded(child: _videoTile('__me__', isMe: true)),
        Expanded(child: _videoTile(allIds[1], isMe: false)),
      ]);
    }
    return GridView.builder(
      padding: const EdgeInsets.all(4),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2, childAspectRatio: 0.85, crossAxisSpacing: 4, mainAxisSpacing: 4,
      ),
      itemCount: count,
      itemBuilder: (_, i) => _videoTile(allIds[i], isMe: allIds[i] == '__me__'),
    );
  }

  Widget _videoTile(String userId, {required bool isMe}) {
    final renderer = isMe ? _localRenderer : _remoteRenderers[userId];
    final name = isMe ? (_myName ?? 'Вы') : _peerName(userId);
    final hasVideo = renderer?.srcObject != null;

    return Stack(fit: StackFit.expand, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: hasVideo
            ? RTCVideoView(renderer!, mirror: isMe,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
            : Container(
                color: isMe ? const Color(0xFF1A2744) : const Color(0xFF1A1D2E),
                child: Center(child: CircleAvatar(
                  radius: 36,
                  backgroundColor: isMe ? const Color(0xFF2AABEE) : Colors.deepPurple,
                  child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: const TextStyle(fontSize: 28, color: Colors.white, fontWeight: FontWeight.w700)),
                )),
              ),
      ),
      // Name label
      Positioned(bottom: 8, left: 8, child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.mic, color: Colors.white, size: 12),
          const SizedBox(width: 4),
          Text(isMe ? '$name (Вы)' : name, style: const TextStyle(color: Colors.white, fontSize: 11)),
        ]),
      )),
      // Muted indicator
      if (isMe && _audioMuted)
        Positioned(top: 8, right: 8, child: Container(
          padding: const EdgeInsets.all(4),
          decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
          child: const Icon(Icons.mic_off, color: Colors.white, size: 12),
        )),
    ]);
  }

  Widget _buildControls() {
    return Container(
      color: const Color(0xFF1C1C1E),
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _ctrlBtn(_audioMuted ? Icons.mic_off : Icons.mic,
            _audioMuted ? Colors.red : Colors.white, _toggleAudio,
            _audioMuted ? 'Микр. выкл' : 'Микр.'),
        _ctrlBtn(_videoMuted ? Icons.videocam_off : Icons.videocam,
            _videoMuted ? Colors.orange : Colors.white, _toggleVideo,
            _videoMuted ? 'Кам. выкл' : 'Камера'),
        _ctrlBtn(_handRaised ? Icons.pan_tool : Icons.pan_tool_outlined,
            _handRaised ? Colors.yellow : Colors.white,
            () => setState(() => _handRaised = !_handRaised), 'Рука'),
        _ctrlBtn(Icons.people_outline, Colors.white, _showParticipants, 'Участники'),
        _ctrlBtn(Icons.call_end, Colors.white, widget.isHost ? _endForAll : _leave, 'Выйти', bg: Colors.red),
      ]),
    );
  }

  Widget _ctrlBtn(IconData icon, Color color, VoidCallback onTap, String label, {Color? bg}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 52, height: 52,
          decoration: BoxDecoration(color: bg ?? const Color(0xFF3A3A3C), shape: BoxShape.circle),
          child: Icon(icon, color: bg != null ? Colors.white : color, size: 24),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 10)),
      ]),
    );
  }

  void _showParticipants() {
    showModalBottomSheet(context: context, builder: (_) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(padding: const EdgeInsets.all(16),
          child: Text('Участники (${_participants.length + 1})',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
        const Divider(height: 0),
        _participantRow(_myName ?? 'Вы', isMe: true),
        ..._participants.map((p) {
          final name = (p['name'] ?? p['userId']?.toString() ?? '?') as String;
          return _participantRow(name, isMe: false);
        }),
        const SizedBox(height: 8),
      ]),
    ));
  }

  @override
  void dispose() { _cleanup(); super.dispose(); }
}
