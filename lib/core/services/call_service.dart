import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../config/app_config.dart';
import 'socket_service.dart';

enum CallState  { outgoing, incoming, active, ended }
enum CallType   { audio, video }

class CallSession {
  final String  callId;
  final String  chatId;
  final String  peerId;
  final String  peerName;
  final CallType type;
  final CallState state;
  final bool isIncoming;
  final MediaStream?   localStream;
  final MediaStream?   remoteStream;
  const CallSession({
    required this.callId, required this.chatId,
    required this.peerId, required this.peerName,
    required this.type,   required this.state,
    this.isIncoming = false,
    this.localStream, this.remoteStream,
  });
  CallSession copyWith({CallState? state, MediaStream? localStream, MediaStream? remoteStream}) =>
      CallSession(callId: callId, chatId: chatId, peerId: peerId, peerName: peerName,
          type: type, state: state ?? this.state, isIncoming: isIncoming,
          localStream: localStream ?? this.localStream, remoteStream: remoteStream ?? this.remoteStream);
}

class CallService {
  static final _instance = CallService._();
  factory CallService() => _instance;
  CallService._();

  final _storage  = const FlutterSecureStorage();
  final _socket   = SocketService();
  final Dio _dio  = Dio(BaseOptions(baseUrl: AppConfig.apiUrl));

  final _sessionCtrl = StreamController<CallSession?>.broadcast();
  Stream<CallSession?> get onSessionChange => _sessionCtrl.stream;

  CallSession? _current;
  CallSession? get current => _current;

  RTCPeerConnection? _pc;
  MediaStream? _localStream;

  int _durationSec = 0;
  Timer? _timer;

  // ICE servers – STUN only (no TURN needed for same-network emulators)
  static const _iceConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };

  StreamSubscription? _subIncoming;
  StreamSubscription? _subAnswered;
  StreamSubscription? _subRejected;
  StreamSubscription? _subEnded;
  StreamSubscription? _subSignal;
  StreamSubscription? _subIce;

  // ── Initialize once ──────────────────────────────────────────────────────
  void init() {
    _subIncoming  ??= _socket.onCallIncoming.listen(_onIncoming);
    _subAnswered  ??= _socket.onCallAnswered.listen(_onAnswered);
    _subRejected  ??= _socket.onCallRejected.listen(_onRejected);
    _subEnded     ??= _socket.onCallEnded.listen(_onEnded);
    _subSignal    ??= _socket.onCallSignal.listen(_onSignal);
    _subIce       ??= _socket.onCallIce.listen(_onIce);
  }

  // ── Incoming call notification ──────────────────────────────────────────
  void _onIncoming(Map<String, dynamic> data) {
    if (_current != null) {
      // Busy — auto-reject
      _socket.emitCallReject(data['callId']?.toString() ?? '', data['from']?.toString() ?? '');
      return;
    }
    final isVideo = data['video'] == true;
    _current = CallSession(
      callId: data['callId']?.toString() ?? '',
      chatId: data['chatId']?.toString() ?? '',
      peerId: data['from']?.toString() ?? '',
      peerName: data['fromName']?.toString() ?? 'Unknown',
      type: isVideo ? CallType.video : CallType.audio,
      state: CallState.incoming,
      isIncoming: true,
    );
    _sessionCtrl.add(_current);
  }

  // ── Callee answered → caller now creates WebRTC offer ───────────────────
  void _onAnswered(Map<String, dynamic> data) {
    if (_current == null || _current!.state != CallState.outgoing) return;
    if (data['callId'] != _current!.callId) return;
    _current = _current!.copyWith(state: CallState.active);
    _sessionCtrl.add(_current);
    _startTimer();
    // Caller creates offer after answer confirmation
    _createAndSendOffer();
  }

  void _onRejected(Map<String, dynamic> data) {
    if (_current == null) return;
    if (data['callId'] != _current!.callId) return;
    _saveCallMessage(_current!.chatId, _current!.type, 'missed', 0);
    _endSession();
  }

  void _onEnded(Map<String, dynamic> data) {
    if (_current == null) return;
    _endSession();
  }

  // ── WebRTC signaling ─────────────────────────────────────────────────────
  void _onSignal(Map<String, dynamic> data) async {
    if (_current == null) return;
    if (data['callId'] != _current!.callId) return;
    final sdpData = data['data'] as Map<dynamic, dynamic>? ?? {};
    final type    = sdpData['type']?.toString() ?? '';
    final sdp     = sdpData['sdp']?.toString() ?? '';

    if (type == 'offer') {
      // We are the callee receiving an offer
      _pc ??= await _createPeerConnection();
      await _pc!.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));
      final answer = await _pc!.createAnswer();
      await _pc!.setLocalDescription(answer);
      _socket.emitCallSignal(_current!.callId, _current!.peerId, {'type': 'answer', 'sdp': answer.sdp});
    } else if (type == 'answer') {
      // We are the caller receiving an answer
      if (_pc != null) {
        await _pc!.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
      }
    }
  }

  void _onIce(Map<String, dynamic> data) async {
    if (_current == null) return;
    if (data['callId'] != _current!.callId) return;
    final c = data['candidate'] as Map<dynamic, dynamic>? ?? {};
    if (c['candidate'] == null) return;
    try {
      await _pc?.addCandidate(RTCIceCandidate(
        c['candidate'].toString(),
        c['sdpMid']?.toString(),
        (c['sdpMLineIndex'] as num?)?.toInt(),
      ));
    } catch (_) {}
  }

  // ── Create RTCPeerConnection ─────────────────────────────────────────────
  Future<RTCPeerConnection> _createPeerConnection() async {
    final pc = await createPeerConnection(_iceConfig);

    // Get local media stream
    try {
      final constraints = _current?.type == CallType.video
          ? {'audio': true, 'video': {'facingMode': 'user', 'width': 320, 'height': 240}}
          : {'audio': true, 'video': false};
      _localStream = await navigator.mediaDevices.getUserMedia(constraints);
      _localStream!.getTracks().forEach((t) => pc.addTrack(t, _localStream!));
      // Update session with local stream
      if (_current != null) {
        _current = _current!.copyWith(localStream: _localStream);
        _sessionCtrl.add(_current);
      }
    } catch (_) {
      // Mic not available on this device — proceed without audio
    }

    // Remote stream
    pc.onTrack = (event) {
      if (event.streams.isNotEmpty && _current != null) {
        _current = _current!.copyWith(remoteStream: event.streams[0]);
        _sessionCtrl.add(_current);
      }
    };

    // ICE candidates
    pc.onIceCandidate = (candidate) {
      if (candidate.candidate != null && _current != null) {
        _socket.emitCallIce(_current!.callId, _current!.peerId, {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        });
      }
    };

    pc.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        if (_current?.state != CallState.active) {
          _current = _current?.copyWith(state: CallState.active);
          _sessionCtrl.add(_current);
          _startTimer();
        }
      }
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _endSession();
      }
    };

    return pc;
  }

  Future<void> _createAndSendOffer() async {
    _pc ??= await _createPeerConnection();
    final offer = await _pc!.createOffer({'offerToReceiveAudio': true, 'offerToReceiveVideo': true});
    await _pc!.setLocalDescription(offer);
    if (_current != null) {
      _socket.emitCallSignal(_current!.callId, _current!.peerId, {'type': 'offer', 'sdp': offer.sdp});
    }
  }

  // ── Public API ──────────────────────────────────────────────────────────
  Future<void> startCall({
    required String chatId,
    required String peerId,
    required String peerName,
    required CallType type,
  }) async {
    if (_current != null) return;
    if (peerId.isEmpty) return;

    final token = await _storage.read(key: 'access_token');
    if (token != null) _dio.options.headers['Authorization'] = 'Bearer $token';

    final callId = 'call_${DateTime.now().millisecondsSinceEpoch}';
    _current = CallSession(
      callId: callId, chatId: chatId,
      peerId: peerId, peerName: peerName,
      type: type, state: CallState.outgoing,
      isIncoming: false,
    );
    _sessionCtrl.add(_current);

    // Notify peer
    final myName = await _storage.read(key: 'user_name') ?? 'Unknown';
    _socket.emitCallStart(callId, chatId, peerId, myName, type == CallType.video);
  }

  Future<void> answerCall() async {
    if (_current == null || _current!.state != CallState.incoming) return;
    final token = await _storage.read(key: 'access_token');
    if (token != null) _dio.options.headers['Authorization'] = 'Bearer $token';

    _current = _current!.copyWith(state: CallState.active);
    _sessionCtrl.add(_current);

    // Notify caller we answered — then they will send us an offer
    _socket.emitCallAnswer(_current!.callId, _current!.peerId);

    // Callee sets up peer connection ready to receive offer
    _pc ??= await _createPeerConnection();

    _startTimer();
  }

  Future<void> rejectCall() async {
    if (_current == null) return;
    _socket.emitCallReject(_current!.callId, _current!.peerId);
    await _saveCallMessage(_current!.chatId, _current!.type, 'missed', 0);
    _endSession();
  }

  Future<void> endCall() async {
    if (_current == null) return;
    final wasActive  = _current!.state == CallState.active;
    final wasOutgoing = _current!.state == CallState.outgoing;
    final callId = _current!.callId;
    final peerId = _current!.peerId;
    final chatId = _current!.chatId;
    final type   = _current!.type;

    _socket.emitCallEnd(callId, peerId);

    if (wasActive) {
      await _saveCallMessage(chatId, type, 'completed', _durationSec);
    } else if (wasOutgoing) {
      await _saveCallMessage(chatId, type, 'missed', 0);
    }
    _endSession();
  }

  // ── Internal ────────────────────────────────────────────────────────────
  void _startTimer() {
    _timer?.cancel();
    _durationSec = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _durationSec++;
    });
  }

  void _endSession() {
    _timer?.cancel();
    _timer = null;
    _current = null;
    _sessionCtrl.add(null);

    // Close WebRTC
    _localStream?.dispose();
    _localStream = null;
    _pc?.close();
    _pc = null;
  }

  Future<void> _saveCallMessage(String chatId, CallType type, String status, int duration) async {
    if (chatId.isEmpty) return;
    final isVideo = type == CallType.video;
    String label;
    if (status == 'completed') {
      label = '${isVideo ? "📹 Видеозвонок" : "📞 Аудиозвонок"} · ${_fmt(duration)}';
    } else if (status == 'missed') {
      label = isVideo ? '📹 Пропущенный видеозвонок' : '📞 Пропущенный звонок';
    } else {
      label = isVideo ? '📹 Видеозвонок' : '📞 Аудиозвонок';
    }
    try {
      await _dio.post('/messages', data: {
        'chatId': chatId,
        'type': 'call',
        'text': label,
        'callInfo': {'type': type.name, 'status': status, 'duration': duration},
      });
    } catch (_) {}
  }

  String _fmt(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return '${m.toString().padLeft(2,'0')}:${s.toString().padLeft(2,'0')}';
  }

  int get durationSec => _durationSec;
}
