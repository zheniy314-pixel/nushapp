import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter/foundation.dart';

/// Типы транспорта в порядке приоритета
enum TransportType { internet, wifiDirect, bluetooth, sms, none }

/// Статус доставки сообщения
enum DeliveryStatus { pending, sent, delivered, failed }

/// Пакет для офлайн-доставки
class NushaPacket {
  final String packetId;
  final String senderId;
  final String recipientId;
  final String recipientPhone; // для SMS
  final Uint8List payload;     // зашифрованное сообщение
  final DateTime createdAt;
  final DateTime expiresAt;
  int attempts;
  List<TransportType> triedTransports;
  DeliveryStatus status;

  NushaPacket({
    required this.packetId,
    required this.senderId,
    required this.recipientId,
    this.recipientPhone = '',
    required this.payload,
    required this.expiresAt,
    this.attempts = 0,
    List<TransportType>? triedTransports,
    this.status = DeliveryStatus.pending,
  })  : createdAt = DateTime.now(),
        triedTransports = triedTransports ?? [];

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// Сериализация в байты для передачи через BT/WiFi
  Uint8List toBytes() {
    final map = {
      'id': packetId,
      'from': senderId,
      'to': recipientId,
      'payload': base64Encode(payload),
      'ts': createdAt.millisecondsSinceEpoch,
      'exp': expiresAt.millisecondsSinceEpoch,
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(map)));
  }

  static NushaPacket? fromBytes(Uint8List bytes) {
    try {
      final map = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      return NushaPacket(
        packetId: map['id'] as String,
        senderId: map['from'] as String,
        recipientId: map['to'] as String,
        payload: base64Decode(map['payload'] as String),
        expiresAt: DateTime.fromMillisecondsSinceEpoch(map['exp'] as int),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Менеджер офлайн-транспортов — главный класс
class TransportManager {
  static final TransportManager _instance = TransportManager._();
  factory TransportManager() => _instance;
  TransportManager._();

  final _connectivity = Connectivity();
  final _outbox = <String, NushaPacket>{};   // packetId -> packet
  final _delivered = <String>{};
  Timer? _retryTimer;

  final _deliveryController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onDelivery => _deliveryController.stream;

  bool _hasInternet = false;
  bool _hasBluetooth = false;

  // ─── Инициализация ─────────────────────────────────────────────────
  Future<void> init() async {
    // Мониторинг сети
    _connectivity.onConnectivityChanged.listen((results) {
      _hasInternet = results.any((r) =>
          r == ConnectivityResult.mobile || r == ConnectivityResult.wifi || r == ConnectivityResult.ethernet);
      if (_hasInternet) _flushOutbox();
    });

    final current = await _connectivity.checkConnectivity();
    _hasInternet = current.any((r) =>
        r == ConnectivityResult.mobile || r == ConnectivityResult.wifi || r == ConnectivityResult.ethernet);

    // Мониторинг Bluetooth
    if (!kIsWeb) {
      FlutterBluePlus.adapterState.listen((state) {
        _hasBluetooth = state == BluetoothAdapterState.on;
      });
    }

    // Периодический retry каждые 30 секунд
    _retryTimer = Timer.periodic(const Duration(seconds: 30), (_) => _flushOutbox());
  }

  // ─── Отправить сообщение ────────────────────────────────────────────
  Future<DeliveryStatus> send(NushaPacket packet) async {
    if (packet.isExpired) return DeliveryStatus.failed;
    _outbox[packet.packetId] = packet;

    return await _tryDeliver(packet);
  }

  Future<DeliveryStatus> _tryDeliver(NushaPacket packet) async {
    // 1. Интернет
    if (_hasInternet && !packet.triedTransports.contains(TransportType.internet)) {
      final ok = await _sendViaInternet(packet);
      if (ok) { _markDelivered(packet); return DeliveryStatus.delivered; }
      packet.triedTransports.add(TransportType.internet);
    }

    // 2. WiFi Direct
    if (!packet.triedTransports.contains(TransportType.wifiDirect)) {
      final ok = await _sendViaWifiDirect(packet);
      if (ok) { _markDelivered(packet); return DeliveryStatus.delivered; }
      packet.triedTransports.add(TransportType.wifiDirect);
    }

    // 3. Bluetooth
    if (_hasBluetooth && !packet.triedTransports.contains(TransportType.bluetooth)) {
      final ok = await _sendViaBluetooth(packet);
      if (ok) { _markDelivered(packet); return DeliveryStatus.delivered; }
      packet.triedTransports.add(TransportType.bluetooth);
    }

    // 4. SMS
    if (packet.recipientPhone.isNotEmpty && !packet.triedTransports.contains(TransportType.sms)) {
      final ok = await _sendViaSms(packet);
      if (ok) { _markDelivered(packet); return DeliveryStatus.delivered; }
      packet.triedTransports.add(TransportType.sms);
    }

    // Всё попробовали — в очередь для повтора
    packet.status = DeliveryStatus.pending;
    packet.attempts++;
    return DeliveryStatus.pending;
  }

  void _markDelivered(NushaPacket packet) {
    packet.status = DeliveryStatus.delivered;
    _outbox.remove(packet.packetId);
    _delivered.add(packet.packetId);
    _deliveryController.add({
      'packetId': packet.packetId,
      'transport': packet.triedTransports.last.name,
      'status': 'delivered',
    });
  }

  Future<void> _flushOutbox() async {
    final expired = _outbox.entries.where((e) => e.value.isExpired).map((e) => e.key).toList();
    for (final id in expired) {
      _outbox.remove(id);
      _deliveryController.add({'packetId': id, 'status': 'expired'});
    }
    for (final packet in _outbox.values.toList()) {
      await _tryDeliver(packet);
    }
  }

  // ─── Транспорт 1: Интернет (WebSocket / HTTP) ──────────────────────
  Future<bool> _sendViaInternet(NushaPacket packet) async {
    // Реализуется через ApiService — отправка через основной канал
    // Здесь вызывается ApiService.sendMessage(packet)
    // Возвращает true если получен ACK от сервера
    try {
      // TODO: вызов ApiService
      return false; // placeholder
    } catch (_) {
      return false;
    }
  }

  // ─── Транспорт 2: WiFi Direct ──────────────────────────────────────
  Future<bool> _sendViaWifiDirect(NushaPacket packet) async {
    // TODO: flutter_p2p_connection или nearby_service
    // Логика: обнаружить peers → найти нужного → установить TCP-сессию → отправить пакет
    return false;
  }

  // ─── Транспорт 3: Bluetooth ────────────────────────────────────────
  Future<bool> _sendViaBluetooth(NushaPacket packet) async {
    if (kIsWeb) return false;
    try {
      // Сканируем BLE устройства Nusha
      final serviceUuid = Guid('4A8B-NUSHA-MSG-v3'.padRight(36, '0').substring(0, 36));
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
      await Future.delayed(const Duration(seconds: 5));
      await FlutterBluePlus.stopScan();

      final results = FlutterBluePlus.lastScanResults;
      for (final r in results) {
        if (r.advertisementData.serviceUuids.contains(serviceUuid)) {
          final device = r.device;
          await device.connect(timeout: const Duration(seconds: 10));
          final services = await device.discoverServices();
          for (final svc in services) {
            for (final char in svc.characteristics) {
              if (char.characteristicUuid == serviceUuid) {
                // Фрагментируем пакет на чанки по 244 байта (BLE MTU)
                final bytes = packet.toBytes();
                const chunkSize = 200;
                for (int i = 0; i < bytes.length; i += chunkSize) {
                  final end = (i + chunkSize < bytes.length) ? i + chunkSize : bytes.length;
                  await char.write(bytes.sublist(i, end));
                }
                await device.disconnect();
                return true;
              }
            }
          }
          await device.disconnect();
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  // ─── Транспорт 4: SMS ─────────────────────────────────────────────
  Future<bool> _sendViaSms(NushaPacket packet) async {
    if (kIsWeb || packet.recipientPhone.isEmpty) return false;
    try {
      // Кодируем пакет в Base64 с префиксом NSH3|
      final encoded = base64Encode(packet.payload);
      // SMS ограничен 160 символами. Длинные — multipart (UDH автоматически)
      const prefix = 'NSH3|';
      final smsBody = '$prefix$encoded';
      // TODO: telephony plugin
      // await Telephony.instance.sendSms(to: packet.recipientPhone, message: smsBody);
      return false; // placeholder до добавления telephony
    } catch (_) {
      return false;
    }
  }

  // ─── Входящий BLE/WiFi пакет ──────────────────────────────────────
  void onIncomingPacket(Uint8List bytes) {
    final packet = NushaPacket.fromBytes(bytes);
    if (packet == null) return;
    if (_delivered.contains(packet.packetId)) return; // дедупликация
    _delivered.add(packet.packetId);
    _deliveryController.add({
      'packetId': packet.packetId,
      'from': packet.senderId,
      'payload': packet.payload,
      'status': 'received',
      'transport': 'bluetooth',
    });
  }

  // ─── Входящий SMS с префиксом NSH3| ──────────────────────────────
  void onIncomingSms(String from, String body) {
    if (!body.startsWith('NSH3|')) return;
    try {
      final encoded = body.substring(5);
      final payload = base64Decode(encoded);
      _deliveryController.add({
        'from': from,
        'payload': payload,
        'status': 'received',
        'transport': 'sms',
      });
    } catch (_) {}
  }

  // ─── Статистика очереди ───────────────────────────────────────────
  Map<String, dynamic> get stats => {
    'outbox': _outbox.length,
    'delivered': _delivered.length,
    'hasInternet': _hasInternet,
    'hasBluetooth': _hasBluetooth,
  };

  void dispose() {
    _retryTimer?.cancel();
    _deliveryController.close();
  }
}
