import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../config/app_config.dart';

/// Центральный Socket.IO сервис — одно подключение для всего приложения
class SocketService {
  static final SocketService _instance = SocketService._();
  factory SocketService() => _instance;
  SocketService._();

  final _storage = const FlutterSecureStorage();
  io.Socket? _socket;
  bool _connected = false;

  // Стримы событий
  final _messageNew     = StreamController<Map<String, dynamic>>.broadcast();
  final _messageDeleted = StreamController<Map<String, dynamic>>.broadcast();
  final _typingStart    = StreamController<Map<String, dynamic>>.broadcast();
  final _typingStop     = StreamController<Map<String, dynamic>>.broadcast();
  final _presenceUpdate = StreamController<Map<String, dynamic>>.broadcast();
  final _callIncoming   = StreamController<Map<String, dynamic>>.broadcast();
  final _callAnswered   = StreamController<Map<String, dynamic>>.broadcast();
  final _callEnded      = StreamController<Map<String, dynamic>>.broadcast();
  final _callRejected   = StreamController<Map<String, dynamic>>.broadcast();
  final _callSignal     = StreamController<Map<String, dynamic>>.broadcast();
  final _callIce        = StreamController<Map<String, dynamic>>.broadcast();
  final _confSignal     = StreamController<Map<String, dynamic>>.broadcast();
  final _confIce        = StreamController<Map<String, dynamic>>.broadcast();
  final _connectionChange = StreamController<bool>.broadcast();

  Stream<Map<String, dynamic>> get onMessageNew      => _messageNew.stream;
  Stream<Map<String, dynamic>> get onMessageDeleted  => _messageDeleted.stream;
  Stream<Map<String, dynamic>> get onTypingStart     => _typingStart.stream;
  Stream<Map<String, dynamic>> get onTypingStop      => _typingStop.stream;
  Stream<Map<String, dynamic>> get onPresenceUpdate  => _presenceUpdate.stream;
  Stream<Map<String, dynamic>> get onCallIncoming    => _callIncoming.stream;
  Stream<Map<String, dynamic>> get onCallAnswered    => _callAnswered.stream;
  Stream<Map<String, dynamic>> get onCallEnded       => _callEnded.stream;
  Stream<Map<String, dynamic>> get onCallRejected    => _callRejected.stream;
  Stream<Map<String, dynamic>> get onCallSignal      => _callSignal.stream;
  Stream<Map<String, dynamic>> get onCallIce         => _callIce.stream;
  Stream<Map<String, dynamic>> get onConfSignal      => _confSignal.stream;
  Stream<Map<String, dynamic>> get onConfIce         => _confIce.stream;
  Stream<bool> get onConnectionChange                => _connectionChange.stream;

  bool get isConnected => _connected;

  Future<void> connect() async {
    if (_socket?.connected == true) return;
    final token = await _storage.read(key: 'access_token');
    if (token == null) return;

    _socket = io.io(AppConfig.socketUrl, io.OptionBuilder()
        .setTransports(['websocket', 'polling'])
        .setAuth({'token': token})
        .enableReconnection()
        .setReconnectionDelay(1000)
        .setReconnectionDelayMax(5000)
        .setReconnectionAttempts(999999)
        .setTimeout(20000)
        .build());

    _socket!
      ..onConnect((_) {
        _connected = true;
        _connectionChange.add(true);
      })
      ..onDisconnect((_) {
        _connected = false;
        _connectionChange.add(false);
      })
      ..on('message:new',     (d) => _messageNew.add(_cast(d)))
      ..on('message:deleted', (d) => _messageDeleted.add(_cast(d)))
      ..on('typing:start',    (d) => _typingStart.add(_cast(d)))
      ..on('typing:stop',     (d) => _typingStop.add(_cast(d)))
      ..on('presence:update', (d) => _presenceUpdate.add(_cast(d)))
      ..on('call:incoming',   (d) => _callIncoming.add(_cast(d)))
      ..on('call:answered',   (d) => _callAnswered.add(_cast(d)))
      ..on('call:ended',      (d) => _callEnded.add(_cast(d)))
      ..on('call:rejected',   (d) => _callRejected.add(_cast(d)))
      ..on('call:signal',     (d) => _callSignal.add(_cast(d)))
      ..on('call:ice',        (d) => _callIce.add(_cast(d)))
      ..on('conf:signal',     (d) => _confSignal.add(_cast(d)))
      ..on('conf:ice',        (d) => _confIce.add(_cast(d)));

    _socket!.connect();
  }

  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _connected = false;
  }

  // ─── Emit helpers ─────────────────────────────────────────────────
  void emitTypingStart(String chatId) => _socket?.emit('typing:start', {'chatId': chatId});
  void emitTypingStop(String chatId)  => _socket?.emit('typing:stop',  {'chatId': chatId});

  void emitCallStart(String callId, String chatId, String to, String fromName, bool video) =>
      _socket?.emit('call:start', {'callId': callId, 'chatId': chatId, 'to': to, 'fromName': fromName, 'video': video});

  void emitCallAnswer(String callId, String to) =>
      _socket?.emit('call:answer', {'callId': callId, 'to': to});

  void emitCallReject(String callId, String to) =>
      _socket?.emit('call:reject', {'callId': callId, 'to': to});

  void emitCallEnd(String callId, String to) =>
      _socket?.emit('call:end', {'callId': callId, 'to': to});

  void emitCallSignal(String callId, String to, Map data) =>
      _socket?.emit('call:signal', {'callId': callId, 'to': to, 'data': data});

  void emitCallIce(String callId, String to, Map candidate) =>
      _socket?.emit('call:ice', {'callId': callId, 'to': to, 'candidate': candidate});

  void emitConfJoin(String roomCode, String name) =>
      _socket?.emit('conf:join', {'roomCode': roomCode, 'name': name});

  void emitConfSignal(String roomCode, String to, Map data) =>
      _socket?.emit('conf:signal', {'roomCode': roomCode, 'to': to, 'data': data});

  void emitConfIce(String roomCode, String to, Map candidate) =>
      _socket?.emit('conf:ice', {'roomCode': roomCode, 'to': to, 'candidate': candidate});

  Map<String, dynamic> _cast(dynamic d) {
    if (d is Map<String, dynamic>) return d;
    if (d is Map) return Map<String, dynamic>.from(d);
    return {};
  }

  void dispose() {
    disconnect();
    _messageNew.close();
    _messageDeleted.close();
    _typingStart.close();
    _typingStop.close();
    _presenceUpdate.close();
    _callIncoming.close();
    _callAnswered.close();
    _callEnded.close();
    _callRejected.close();
    _callSignal.close();
    _callIce.close();
    _confSignal.close();
    _confIce.close();
    _connectionChange.close();
  }
}
