import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/app_config.dart';

/// Центральный сервис API — все запросы к серверу
class ApiService {
  static final ApiService _instance = ApiService._();
  factory ApiService() => _instance;
  ApiService._();

  final _storage = const FlutterSecureStorage();
  late final Dio _dio;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _dio = Dio(BaseOptions(
      baseUrl: AppConfig.apiUrl,
      connectTimeout: const Duration(seconds: AppConfig.connectTimeoutSec),
      receiveTimeout: const Duration(seconds: AppConfig.receiveTimeoutSec),
    ));

    // Interceptor: добавляет токен к каждому запросу
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (opts, handler) async {
        final token = await _storage.read(key: 'access_token');
        if (token != null) opts.headers['Authorization'] = 'Bearer $token';
        handler.next(opts);
      },
      onError: (err, handler) async {
        // 401 → попробовать refresh
        if (err.response?.statusCode == 401) {
          final refreshed = await _tryRefresh();
          if (refreshed) {
            final token = await _storage.read(key: 'access_token');
            err.requestOptions.headers['Authorization'] = 'Bearer $token';
            final retry = await _dio.fetch(err.requestOptions);
            handler.resolve(retry);
            return;
          }
          await _logout();
        }
        handler.next(err);
      },
    ));

    _initialized = true;
  }

  Future<bool> _tryRefresh() async {
    try {
      final refresh = await _storage.read(key: 'refresh_token');
      if (refresh == null) return false;
      final r = await Dio().post('${AppConfig.apiUrl}/auth/refresh',
          options: Options(receiveTimeout: const Duration(seconds: 10)),
          data: {'refreshToken': refresh});
      await _storage.write(key: 'access_token',  value: r.data['accessToken']);
      await _storage.write(key: 'refresh_token', value: r.data['refreshToken']);
      // Обновить заголовок в текущем dio
      _dio.options.headers['Authorization'] = 'Bearer ${r.data['accessToken']}';
      return true;
    } catch (_) { return false; }
  }

  /// Обновить токены по refresh token (вызывается при запуске)
  Future<Map<String, dynamic>?> refreshTokens(String refreshToken) async {
    try {
      final r = await Dio(BaseOptions(
        baseUrl: AppConfig.apiUrl,
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      )).post('/auth/refresh', data: {'refreshToken': refreshToken});
      return r.data as Map<String, dynamic>;
    } catch (_) { return null; }
  }

  Future<void> _logout() async {
    await _storage.deleteAll();
  }

  Dio get dio => _dio;

  // ─── Auth ───────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> register(String email, String login, String name, String password) async {
    final r = await _dio.post('/auth/register', data: {'email': email, 'login': login, 'name': name, 'password': password});
    return r.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> login(String credential, String password) async {
    final r = await _dio.post('/auth/login', data: {'credential': credential, 'password': password});
    return r.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getMe() async {
    final r = await _dio.get('/auth/me');
    return r.data as Map<String, dynamic>;
  }

  // ─── Chats ──────────────────────────────────────────────────────────
  Future<List<dynamic>> getChats() async {
    final r = await _dio.get('/chats');
    return r.data['chats'] as List;
  }

  Future<Map<String, dynamic>> getOrCreateDirectChat(String targetUserId) async {
    final r = await _dio.post('/chats/direct', data: {'targetUserId': targetUserId});
    return r.data['chat'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createGroup(String title, List<String> memberIds) async {
    final r = await _dio.post('/chats/group', data: {'title': title, 'memberIds': memberIds});
    return r.data['chat'] as Map<String, dynamic>;
  }

  // ─── Messages ───────────────────────────────────────────────────────
  Future<List<dynamic>> getMessages(String chatId, {int page = 1}) async {
    final r = await _dio.get('/messages/$chatId', queryParameters: {'page': page});
    return r.data['messages'] as List;
  }

  Future<Map<String, dynamic>> sendMessage({
    required String chatId,
    required String text,
    String type = 'text',
    String? mediaUrl,
    String? replyTo,
  }) async {
    final r = await _dio.post('/messages', data: {
      'chatId': chatId, 'text': text, 'type': type,
      if (mediaUrl != null) 'mediaUrl': mediaUrl,
      if (replyTo != null) 'replyTo': replyTo,
    });
    return r.data['message'] as Map<String, dynamic>;
  }

  Future<void> deleteMessage(String messageId) async {
    await _dio.delete('/messages/$messageId');
  }

  // ─── Users ──────────────────────────────────────────────────────────
  Future<List<dynamic>> searchUsers(String q) async {
    final r = await _dio.get('/users/search', queryParameters: {'q': q});
    return r.data['users'] as List;
  }

  Future<Map<String, dynamic>> getUserByLogin(String login) async {
    final r = await _dio.get('/users/by-login/$login');
    return r.data['user'] as Map<String, dynamic>;
  }

  // ─── Mail ───────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> getMailFolders() async {
    final r = await _dio.get('/mail/folders');
    return r.data['folders'] as Map<String, dynamic>;
  }

  Future<List<dynamic>> getMails(String folder, {int page = 1}) async {
    final r = await _dio.get('/mail/$folder', queryParameters: {'page': page});
    return r.data['mails'] as List;
  }

  Future<void> sendMail({
    required List<String> to,
    List<String> cc = const [],
    String subject = '',
    String bodyText = '',
    String? replyToId,
  }) async {
    await _dio.post('/mail/send', data: {
      'to': to, 'cc': cc, 'subject': subject, 'bodyText': bodyText, 'bodyHtml': bodyText,
      if (replyToId != null) 'replyToId': replyToId,
    });
  }

  Future<String?> getMyMailAddress() async {
    try {
      final r = await _dio.get('/mail/address/mine');
      return r.data['nusha_address'] as String?;
    } catch (_) { return null; }
  }

  // ─── Conferences ────────────────────────────────────────────────────
  Future<Map<String, dynamic>> createConference({
    String title = 'Конференция',
    String platform = 'mobile',
  }) async {
    final r = await _dio.post('/conferences/create', data: {'title': title, 'platform': platform});
    return r.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> joinConference(String roomCode, {String? pin, String platform = 'mobile'}) async {
    final r = await _dio.post('/conferences/join', data: {
      'roomCode': roomCode, 'platform': platform, if (pin != null) 'pin': pin,
    });
    return r.data as Map<String, dynamic>;
  }

  Future<void> leaveConference(String roomCode) async {
    await _dio.post('/conferences/$roomCode/leave');
  }

  // ─── Stories ────────────────────────────────────────────────────────
  Future<List<dynamic>> getStoriesFeed() async {
    final r = await _dio.get('/stories/feed');
    return r.data['stories'] as List;
  }

  Future<void> createStory({
    required String mediaType,
    String? mediaUrl,
    String? textContent,
    String bgColor = '#000000',
  }) async {
    await _dio.post('/stories', data: {
      'mediaType': mediaType,
      if (mediaUrl != null) 'mediaUrl': mediaUrl,
      if (textContent != null) 'textContent': textContent,
      'bgColor': bgColor,
    });
  }

  // ─── TURN credentials ────────────────────────────────────────────────
  Future<List<dynamic>> getTurnCredentials() async {
    try {
      final r = await _dio.get('/calls/turn-credentials');
      return r.data['iceServers'] as List;
    } catch (_) {
      return [{'urls': 'stun:stun.l.google.com:19302'}];
    }
  }

  // ─── Files ───────────────────────────────────────────────────────────
  Future<String?> uploadFile(String filePath, String mimeType) async {
    try {
      final form = FormData.fromMap({'file': await MultipartFile.fromFile(filePath, contentType: DioMediaType.parse(mimeType))});
      final r = await _dio.post('/files/upload', data: form);
      return r.data['url'] as String?;
    } catch (_) { return null; }
  }

  // ─── Settings ────────────────────────────────────────────────────────
  Future<void> updatePushToken(String token, String platform) async {
    await _dio.patch('/settings/push-token', data: {'token': token, 'platform': platform});
  }

  Future<void> changePassword(String current, String next) async {
    await _dio.patch('/settings/password', data: {'currentPassword': current, 'newPassword': next});
  }
}
