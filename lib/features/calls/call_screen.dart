import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../core/api/api_service.dart';
import '../../core/services/socket_service.dart';
import 'dart:async';

enum CallState { ringing, connecting, active, ended }
enum CallKind  { audio, video }

class CallScreen extends StatefulWidget {
  final String callId;
  final String peerId;
  final String peerName;
  final String? peerAvatar;
  final CallKind kind;
  final bool isIncoming;
  final Map? initialSdp;

  const CallScreen({
    super.key,
    required this.callId,
    required this.peerId,
    required this.peerName,
    this.peerAvatar,
    this.kind = CallKind.audio,
    this.isIncoming = false,
    this.initialSdp,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final _api    = ApiService();
  final _socket = SocketService();

  final _localRenderer  = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  RTCPeerConnection? _pc;
  MediaStream? _localStream;

  CallState _state = CallState.ringing;
  bool _audioMuted = false;
  bool _videoMuted = false;
  bool _speakerOn  = true;
  int _elapsed     = 0;
  Timer? _timer;

  late final List<StreamSubscription> _subs;

  @override
  void initState() {
    super.initState();
    _initRenderers();
    _setupListeners();
    if (!widget.isIncoming) _startCall();
    else setState(() => _state = CallState.ringing);
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  void _setupListeners() {
    _subs = [
      _socket.onCallAnswered.listen((d) {
        if (d['callId'] == widget.callId) _handleAnswered(d);
      }),
      _socket.onCallEnded.listen((d) {
        if (d['callId'] == widget.callId) _handleEnded();
      }),
      _socket.onCallRejected.listen((d) {
        if (d['callId'] == widget.callId) _handleRejected();
      }),
      _socket.onCallIce.listen((d) {
        if (d['callId'] == widget.callId) _handleIce(d);
      }),
    ];
  }

  Future<void> _startCall() async {
    setState(() => _state = CallState.connecting);
    await _setupPeerConnection();

    final offer = await _pc!.createOffer(widget.kind == CallKind.video
        ? {'offerToReceiveVideo': true, 'offerToReceiveAudio': true}
        : {'offerToReceiveAudio': true});
    await _pc!.setLocalDescription(offer);

    _socket.emitConfSignal(widget.callId, widget.peerId,
        {'type': 'offer', 'sdp': offer.sdp, 'callId': widget.callId});
  }

  Future<void> _answerCall() async {
    setState(() => _state = CallState.connecting);
    await _setupPeerConnection();

    if (widget.initialSdp != null) {
      await _pc!.setRemoteDescription(RTCSessionDescription(widget.initialSdp!['sdp'], 'offer'));
    }

    final answer = await _pc!.createAnswer();
    await _pc!.setLocalDescription(answer);

    _socket.emitCallIce(widget.callId, widget.peerId,
        {'type': 'answer', 'sdp': answer.sdp});
  }

  Future<void> _setupPeerConnection() async {
    final iceServers = await _api.getTurnCredentials();
    _pc = await createPeerConnection({'iceServers': iceServers});

    // Локальный стрим
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': widget.kind == CallKind.video
          ? {'facingMode': 'user', 'width': 640, 'height': 480}
          : false,
    });
    _localRenderer.srcObject = _localStream;
    _localStream!.getTracks().forEach((t) => _pc!.addTrack(t, _localStream!));

    _pc!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        setState(() => _remoteRenderer.srcObject = event.streams[0]);
      }
    };

    _pc!.onIceCandidate = (candidate) {
      if (candidate.candidate != null) {
        _socket.emitCallIce(widget.callId, widget.peerId, {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        });
      }
    };

    _pc!.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        setState(() => _state = CallState.active);
        _startTimer();
      }
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _handleEnded();
      }
    };
  }

  Future<void> _handleAnswered(Map d) async {
    if (d['sdp'] != null) {
      await _pc?.setRemoteDescription(RTCSessionDescription(d['sdp'], 'answer'));
    }
    setState(() => _state = CallState.active);
    _startTimer();
  }

  Future<void> _handleIce(Map d) async {
    final c = d['candidate'];
    if (c == null) return;
    await _pc?.addCandidate(RTCIceCandidate(c['candidate'], c['sdpMid'], c['sdpMLineIndex']));
  }

  void _handleEnded() {
    setState(() => _state = CallState.ended);
    _timer?.cancel();
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  void _handleRejected() {
    _handleEnded();
  }

  Future<void> _hangup() async {
    try {
      await _api.dio.post('/calls/hangup', data: {'callId': widget.callId}).catchError((_) {});
    } catch (_) {}
    _handleEnded();
  }

  void _toggleAudio() {
    final tracks = _localStream?.getAudioTracks() ?? [];
    for (final t in tracks) t.enabled = _audioMuted;
    setState(() => _audioMuted = !_audioMuted);
  }

  void _toggleVideo() {
    final tracks = _localStream?.getVideoTracks() ?? [];
    for (final t in tracks) t.enabled = _videoMuted;
    setState(() => _videoMuted = !_videoMuted);
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed++);
    });
  }

  String get _elapsedStr {
    final m = _elapsed ~/ 60;
    final s = _elapsed % 60;
    return '${m.toString().padLeft(2,'0')}:${s.toString().padLeft(2,'0')}';
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final s in _subs) s.cancel();
    _localStream?.dispose();
    _pc?.close();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Фон: удалённое видео или градиент
          Positioned.fill(
            child: widget.kind == CallKind.video && _state == CallState.active
                ? RTCVideoView(_remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                : Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter, end: Alignment.bottomCenter,
                        colors: [Color(0xFF1A237E), Color(0xFF0D47A1)],
                      ),
                    ),
                  ),
          ),

          // Локальное видео (PiP)
          if (widget.kind == CallKind.video && _state == CallState.active)
            Positioned(
              top: 100, right: 16,
              width: 100, height: 140,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: RTCVideoView(_localRenderer, mirror: true,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
              ),
            ),

          // Основной контент
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 60),
                // Аватар
                CircleAvatar(
                  radius: 60,
                  backgroundColor: Colors.white.withOpacity(0.2),
                  backgroundImage: widget.peerAvatar != null ? NetworkImage(widget.peerAvatar!) : null,
                  child: widget.peerAvatar == null
                      ? Text(widget.peerName.isNotEmpty ? widget.peerName[0].toUpperCase() : '?',
                          style: const TextStyle(fontSize: 48, color: Colors.white))
                      : null,
                ),
                const SizedBox(height: 20),

                // Имя
                Text(widget.peerName,
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600, color: Colors.white)),
                const SizedBox(height: 8),

                // Статус
                Text(_stateLabel(),
                    style: const TextStyle(fontSize: 16, color: Colors.white70)),

                if (_state == CallState.active) ...[
                  const SizedBox(height: 4),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.lock, size: 14, color: Colors.white54),
                    const SizedBox(width: 4),
                    Text(_elapsedStr, style: const TextStyle(color: Colors.white54)),
                  ]),
                ],

                const Spacer(),

                // Кнопки управления
                if (_state == CallState.ringing && widget.isIncoming)
                  _buildIncomingButtons()
                else
                  _buildActiveButtons(),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _stateLabel() {
    switch (_state) {
      case CallState.ringing:    return widget.isIncoming ? 'Входящий звонок...' : 'Вызов...';
      case CallState.connecting: return 'Соединение...';
      case CallState.active:     return widget.kind == CallKind.video ? 'Видеозвонок' : 'Аудиозвонок';
      case CallState.ended:      return 'Завершён';
    }
  }

  Widget _buildIncomingButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _roundBtn(Icons.call_end, Colors.red, 'Отклонить', () async {
          await _api.dio.post('/calls/reject', data: {'callId': widget.callId}).catchError((_) {});
          if (mounted) Navigator.of(context).pop();
        }),
        _roundBtn(Icons.call, Colors.green, 'Принять', _answerCall, size: 72),
      ],
    );
  }

  Widget _buildActiveButtons() {
    return Column(children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _roundBtn(_audioMuted ? Icons.mic_off : Icons.mic,
              _audioMuted ? Colors.white24 : Colors.white24, _audioMuted ? 'Вкл. микр.' : 'Микр.', _toggleAudio),
          if (widget.kind == CallKind.video)
            _roundBtn(_videoMuted ? Icons.videocam_off : Icons.videocam,
                Colors.white24, _videoMuted ? 'Вкл. кам.' : 'Камера', _toggleVideo),
          _roundBtn(Icons.volume_up, _speakerOn ? const Color(0xFF2AABEE) : Colors.white24,
              'Динамик', () => setState(() => _speakerOn = !_speakerOn)),
          _roundBtn(Icons.call_end, Colors.red, 'Завершить', _hangup, size: 64),
        ],
      ),
    ]);
  }

  Widget _roundBtn(IconData icon, Color bg, String label, VoidCallback onTap, {double size = 56}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: size, height: size,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          child: Icon(icon, color: Colors.white, size: size * 0.45),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
      ]),
    );
  }
}
