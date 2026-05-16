import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dio/dio.dart';
import '../../core/config/app_config.dart';
import '../../core/services/background_service.dart';
import '../../core/services/global_notif_listener.dart';
import '../chats/main_screen.dart';

// Auth flow states
enum _AuthStep { form, otpSent, otpVerify }

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _storage = const FlutterSecureStorage();
  final _dio = Dio(BaseOptions(baseUrl: AppConfig.apiUrl, connectTimeout: const Duration(seconds: 15)));

  bool _isLogin = true;
  bool _loading = false;
  String? _error;
  _AuthStep _step = _AuthStep.form;

  final _credCtrl  = TextEditingController();
  final _passCtrl  = TextEditingController();
  final _nameCtrl  = TextEditingController();
  final _loginCtrl = TextEditingController();
  final _otpCtrl   = TextEditingController();

  // For OTP verification — stores temp userId
  String? _pendingUserId;
  String? _pendingEmail;

  bool _passVisible = false;

  @override
  void dispose() {
    _credCtrl.dispose(); _passCtrl.dispose();
    _nameCtrl.dispose(); _loginCtrl.dispose(); _otpCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;
    setState(() { _loading = true; _error = null; });
    try {
      if (_isLogin) {
        await _login();
      } else {
        await _register();
      }
    } on DioException catch (e) {
      final msg = e.response?.data?['message'] ?? e.response?.data?['error'] ?? e.message ?? 'Ошибка соединения';
      setState(() { _error = msg.toString(); });
    } catch (e) {
      setState(() { _error = e.toString(); });
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _login() async {
    final resp = await _dio.post('/auth/login', data: {
      'credential': _credCtrl.text.trim(),
      'password':   _passCtrl.text,
    });
    await _saveTokens(resp.data);
    if (mounted) _goToMain();
  }

  Future<void> _register() async {
    // Step 1: send registration — server sends OTP to email
    final resp = await _dio.post('/auth/register', data: {
      'email':    _credCtrl.text.trim().toLowerCase(),
      'login':    _loginCtrl.text.trim().toLowerCase(),
      'name':     _nameCtrl.text.trim(),
      'password': _passCtrl.text,
    });
    final data = resp.data as Map<String, dynamic>;

    // If server returns tokens immediately (no OTP required)
    if (data['accessToken'] != null) {
      await _saveTokens(data);
      if (mounted) _goToMain();
      return;
    }

    // Server requires OTP verification
    _pendingUserId = data['userId'] ?? data['user']?['id'];
    _pendingEmail  = _credCtrl.text.trim().toLowerCase();
    setState(() { _step = _AuthStep.otpSent; });
  }

  Future<void> _verifyOtp() async {
    if (_loading) return;
    final otp = _otpCtrl.text.trim();
    if (otp.length < 4) { setState(() => _error = 'Введите код из письма'); return; }
    setState(() { _loading = true; _error = null; });
    try {
      final resp = await _dio.post('/auth/verify-otp', data: {
        'userId': _pendingUserId,
        'otp':    otp,
        'email':  _pendingEmail,
      });
      await _saveTokens(resp.data);
      if (mounted) _goToMain();
    } on DioException catch (e) {
      setState(() { _error = e.response?.data?['message'] ?? 'Неверный код'; });
    } finally { setState(() => _loading = false); }
  }

  Future<void> _resendOtp() async {
    if (_pendingEmail == null) return;
    try {
      await _dio.post('/auth/resend-otp', data: {'email': _pendingEmail, 'userId': _pendingUserId});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Код отправлен повторно'), backgroundColor: Colors.green));
    } catch (_) {}
  }

  Future<void> _saveTokens(Map<String, dynamic> data) async {
    final accessToken  = data['accessToken']  ?? data['access_token']  ?? '';
    final refreshToken = data['refreshToken'] ?? data['refresh_token'] ?? '';
    final user = data['user'] as Map<String, dynamic>? ?? {};
    final userId = (user['_id'] ?? user['id'] ?? '').toString();
    await _storage.write(key: 'access_token',  value: accessToken);
    await _storage.write(key: 'refresh_token', value: refreshToken);
    await _storage.write(key: 'user_id',       value: userId);
    await _storage.write(key: 'user_email',    value: user['email'] ?? _credCtrl.text.trim());
    await _storage.write(key: 'user_name',     value: user['name'] ?? '');

    // ── Notify global listener + background service with fresh credentials ──
    if (accessToken.isNotEmpty) {
      GlobalNotifListener().updateUserId(userId);
      notifyBackgroundServiceLogin(token: accessToken, userId: userId);
    }
  }

  void _goToMain() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(pageBuilder: (_, __, ___) => const MainScreen(), transitionDuration: Duration.zero),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            const SizedBox(height: 48),
            // Logo
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF2AABEE), Color(0xFF007AFF)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.lock_outline, color: Colors.white, size: 40),
            ),
            const SizedBox(height: 20),
            Text(
              _step == _AuthStep.otpSent || _step == _AuthStep.otpVerify
                  ? 'Подтверждение Email'
                  : (_isLogin ? 'Вход в Нуша' : 'Регистрация'),
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              _step == _AuthStep.otpSent
                  ? 'Мы отправили код подтверждения на\n${_pendingEmail ?? "ваш email"}'
                  : (_isLogin
                      ? 'Введите логин или email и пароль'
                      : 'Создайте аккаунт @nushik.info'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 14),
            ),
            const SizedBox(height: 32),

            if (_step == _AuthStep.otpSent || _step == _AuthStep.otpVerify)
              _otpForm()
            else
              _authForm(),

            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13))),
                ]),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _authForm() {
    return Column(children: [
      // Tabs Login / Register
      Container(
        decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          _tabBtn('Вход',        _isLogin, () => setState(() { _isLogin = true; _error = null; })),
          _tabBtn('Регистрация', !_isLogin, () => setState(() { _isLogin = false; _error = null; })),
        ]),
      ),
      const SizedBox(height: 24),

      if (!_isLogin) ...[
        _field(_nameCtrl, 'Ваше имя', Icons.person_outline),
        const SizedBox(height: 12),
        _field(_loginCtrl, 'Логин (@username)', Icons.alternate_email),
        const SizedBox(height: 12),
      ],

      _field(_credCtrl, _isLogin ? 'Логин или Email' : 'Email (станет @nushik.info)', Icons.mail_outline),
      const SizedBox(height: 12),

      // Password field
      TextField(
        controller: _passCtrl,
        obscureText: !_passVisible,
        decoration: InputDecoration(
          labelText: 'Пароль',
          prefixIcon: const Icon(Icons.lock_outline),
          suffixIcon: IconButton(
            icon: Icon(_passVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined),
            onPressed: () => setState(() => _passVisible = !_passVisible),
          ),
          filled: true, fillColor: const Color(0xFFF5F5F5),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        ),
      ),

      if (!_isLogin) ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFF2AABEE).withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            const Icon(Icons.mail_outline, color: Color(0xFF2AABEE), size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(
              'После регистрации на ваш email придёт код OTP для подтверждения',
              style: const TextStyle(color: Color(0xFF2AABEE), fontSize: 12),
            )),
          ]),
        ),
      ],

      const SizedBox(height: 24),

      ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF2AABEE),
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: _loading ? null : _submit,
        child: _loading
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Text(_isLogin ? 'Войти' : 'Зарегистрироваться', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
      ),

      if (_isLogin) ...[
        const SizedBox(height: 16),
        TextButton(onPressed: () {}, child: const Text('Забыли пароль?', style: TextStyle(color: Color(0xFF2AABEE)))),
      ],
    ]);
  }

  Widget _otpForm() {
    return Column(children: [
      // OTP illustration
      Container(
        width: 80, height: 80, margin: const EdgeInsets.only(bottom: 24),
        decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), shape: BoxShape.circle),
        child: const Icon(Icons.mark_email_read_outlined, color: Colors.green, size: 44),
      ),

      // OTP input — 6 boxes
      Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(6, (i) {
        return Container(
          width: 44, height: 52, margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF2AABEE).withOpacity(0.3), width: 1.5),
          ),
          alignment: Alignment.center,
          child: Text(
            _otpCtrl.text.length > i ? _otpCtrl.text[i] : '',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
        );
      })),

      const SizedBox(height: 12),

      // Hidden OTP real input
      TextField(
        controller: _otpCtrl,
        keyboardType: TextInputType.number,
        maxLength: 6,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: const TextStyle(fontSize: 1, color: Colors.transparent),
        cursorColor: Colors.transparent,
        decoration: const InputDecoration(counterText: '', border: InputBorder.none),
        autofocus: true,
        onChanged: (v) => setState(() {}),
      ),

      const SizedBox(height: 4),
      const Text('Введите 6-значный код из письма', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 13)),
      const SizedBox(height: 24),

      ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: _loading ? null : _verifyOtp,
        child: _loading
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Text('Подтвердить код', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
      ),

      const SizedBox(height: 16),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('Не получили код? ', style: TextStyle(color: Color(0xFF8E8E93))),
        TextButton(
          onPressed: _resendOtp,
          child: const Text('Отправить снова', style: TextStyle(color: Color(0xFF2AABEE), fontWeight: FontWeight.w600)),
        ),
      ]),
      TextButton(
        onPressed: () => setState(() { _step = _AuthStep.form; _error = null; }),
        child: const Text('← Изменить данные', style: TextStyle(color: Color(0xFF8E8E93))),
      ),
    ]);
  }

  Widget _field(TextEditingController ctrl, String label, IconData icon, {bool obscure = false}) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label, prefixIcon: Icon(icon),
        filled: true, fillColor: const Color(0xFFF5F5F5),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
    );
  }

  Widget _tabBtn(String label, bool active, VoidCallback onTap) {
    return Expanded(child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        margin: active ? const EdgeInsets.all(4) : EdgeInsets.zero,
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: active ? [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4)] : [],
        ),
        alignment: Alignment.center,
        child: Text(label, style: TextStyle(fontWeight: active ? FontWeight.w700 : FontWeight.w500, color: active ? Colors.black : const Color(0xFF8E8E93))),
      ),
    ));
  }
}
