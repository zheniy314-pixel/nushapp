import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/api/api_service.dart';
import 'conference_screen.dart';
import 'dart:io' show Platform;

/// Экран создания и подключения к конференции
class JoinConferenceScreen extends StatefulWidget {
  const JoinConferenceScreen({super.key});

  @override
  State<JoinConferenceScreen> createState() => _JoinConferenceScreenState();
}

class _JoinConferenceScreenState extends State<JoinConferenceScreen> {
  final _api = ApiService();
  final _codeCtrl = TextEditingController();
  final _titleCtrl = TextEditingController(text: 'Конференция');
  bool _loading = false;
  String? _error;

  bool get _isDesktop =>
      !Platform.isIOS && !Platform.isAndroid;

  String get _platform => _isDesktop ? 'desktop' : 'mobile';

  int get _maxParticipants => _isDesktop ? 50 : 5;

  Future<void> _create() async {
    setState(() { _loading = true; _error = null; });
    try {
      final result = await _api.createConference(
        title: _titleCtrl.text.trim().isEmpty ? 'Конференция' : _titleCtrl.text.trim(),
        platform: _platform,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => ConferenceScreen(
          roomCode: result['roomCode'] as String,
          title: _titleCtrl.text.trim(),
          isHost: true,
        ),
      ));
    } catch (e) {
      setState(() => _error = 'Ошибка создания: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _join() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.length < 6) { setState(() => _error = 'Введите код комнаты'); return; }
    setState(() { _loading = true; _error = null; });
    try {
      final result = await _api.joinConference(code, platform: _platform);
      if (!mounted) return;
      final conf = result['conference'] as Map<String, dynamic>;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => ConferenceScreen(
          roomCode: code,
          title: conf['title'] as String? ?? 'Конференция',
          isHost: false,
        ),
      ));
    } on Exception catch (e) {
      final msg = e.toString();
      if (msg.contains('room_full')) {
        setState(() => _error = _isDesktop
            ? 'Комната заполнена (максимум $_maxParticipants участников)'
            : 'Комната заполнена. Максимум 5 человек на мобильном.\nПереключитесь на компьютер для большего числа.');
      } else if (msg.contains('wrong_pin')) {
        setState(() => _error = 'Неверный PIN-код');
      } else {
        setState(() => _error = 'Комната не найдена');
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _titleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Конференция')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Информация о лимите
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF2AABEE).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                const Icon(Icons.info_outline, color: Color(0xFF2AABEE)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _isDesktop
                        ? 'Компьютер: до 50 участников с видео'
                        : 'Телефон: до 5 участников с видео.\nДля большего числа используйте компьютер.',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 32),

            // Создать конференцию
            const Text('Создать новую', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                hintText: 'Название конференции',
                prefixIcon: Icon(Icons.videocam_outlined),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _loading ? null : _create,
                icon: const Icon(Icons.add),
                label: Text('Создать (макс. $_maxParticipants чел.)'),
              ),
            ),

            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 24),

            // Войти по коду
            const Text('Войти по коду', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            TextField(
              controller: _codeCtrl,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Z0-9a-z]')),
                LengthLimitingTextInputFormatter(10),
              ],
              decoration: const InputDecoration(
                hintText: 'Код комнаты (напр. ABCD1234)',
                prefixIcon: Icon(Icons.meeting_room_outlined),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                onPressed: _loading ? null : _join,
                icon: const Icon(Icons.login),
                label: const Text('Войти'),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF2AABEE)),
                  foregroundColor: const Color(0xFF2AABEE),
                ),
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  const Icon(Icons.warning_amber, color: Colors.red, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!, style: const TextStyle(color: Colors.red))),
                ]),
              ),
            ],

            if (_loading) ...[
              const SizedBox(height: 24),
              const Center(child: CircularProgressIndicator()),
            ],
          ],
        ),
      ),
    );
  }
}
