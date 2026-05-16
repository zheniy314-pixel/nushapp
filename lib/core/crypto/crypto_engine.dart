import 'dart:typed_data';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:convert/convert.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Криптографический движок — хранение ключей, хэши, базовое шифрование
/// Полноценный Double Ratchet реализуется через libsignal (нативная библиотека)
class CryptoEngine {
  static final CryptoEngine _instance = CryptoEngine._();
  factory CryptoEngine() => _instance;
  CryptoEngine._();

  final _storage = const FlutterSecureStorage();

  // ─── Генерация и хранение Identity Key ──────────────────────────
  Future<String?> getIdentityKeyPublic() async {
    return _storage.read(key: 'identity_key_pub');
  }

  Future<bool> hasIdentityKey() async {
    final key = await _storage.read(key: 'identity_key_pub');
    return key != null && key.isNotEmpty;
  }

  /// Генерирует identity key pair (заглушка — в проде через libsignal)
  Future<Map<String, String>> generateIdentityKey() async {
    // TODO: заменить на libsignal: SignalProtocolAddress + KeyHelper
    final random = Uint8List(32);
    for (int i = 0; i < 32; i++) random[i] = DateTime.now().microsecond % 256;
    final pub = hex.encode(sha256.convert(random).bytes);
    final priv = hex.encode(random);
    await _storage.write(key: 'identity_key_pub', value: pub);
    await _storage.write(key: 'identity_key_priv', value: priv);
    return {'publicKey': pub, 'privateKey': priv};
  }

  // ─── Генерация PreKeys для X3DH ─────────────────────────────────
  Future<List<Map<String, String>>> generateOneTimePreKeys(int count) async {
    final keys = <Map<String, String>>[];
    for (int i = 0; i < count; i++) {
      final id = DateTime.now().microsecondsSinceEpoch + i;
      final random = Uint8List(32);
      for (int j = 0; j < 32; j++) random[j] = (id + j) % 256;
      keys.add({'keyId': '$id', 'publicKey': hex.encode(sha256.convert(random).bytes)});
    }
    return keys;
  }

  // ─── Хэш для дедупликации пакетов ──────────────────────────────
  String hashPacket(Uint8List data) {
    return hex.encode(sha256.convert(data).bytes);
  }

  // ─── Простое симметричное шифрование для локального хранения ───
  /// AES-256-GCM через Dart isolate (в продакшн — через flutter_sodium)
  Uint8List encryptLocal(Uint8List data, String key) {
    // Placeholder: XOR с ключом (в проде использовать flutter_sodium)
    final keyBytes = sha256.convert(utf8.encode(key)).bytes;
    final result = Uint8List(data.length);
    for (int i = 0; i < data.length; i++) {
      result[i] = data[i] ^ keyBytes[i % keyBytes.length];
    }
    return result;
  }

  Uint8List decryptLocal(Uint8List data, String key) => encryptLocal(data, key);

  // ─── Safety Numbers (верификация контакта) ─────────────────────
  String computeSafetyNumbers(String myKey, String theirKey) {
    final combined = [myKey, theirKey]..sort();
    final hash = sha256.convert(utf8.encode(combined.join(':'))).bytes;
    // Форматируем как 12 групп по 5 цифр (как у Signal)
    final digits = hex.encode(hash).codeUnits
        .map((c) => (c >= 48 && c <= 57) ? c - 48 : c % 10)
        .toList();
    final groups = <String>[];
    for (int i = 0; i < 60 && i < digits.length; i += 5) {
      final end = (i + 5 < digits.length) ? i + 5 : digits.length;
      groups.add(digits.sublist(i, end).join());
    }
    return groups.join(' ');
  }

  // ─── Паника: уничтожить все ключи ───────────────────────────────
  Future<void> panicWipeKeys() async {
    final keysToDelete = [
      'identity_key_pub', 'identity_key_priv',
      'signed_prekey', 'access_token', 'refresh_token',
      'user_id', 'user_email', 'secret_pin', 'panic_pin',
    ];
    for (final key in keysToDelete) {
      await _storage.delete(key: key);
    }
  }
}
