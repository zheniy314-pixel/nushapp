import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/config/app_config.dart';

class MailSettings extends StatefulWidget {
  const MailSettings({super.key});
  @override State<MailSettings> createState() => _MailSettingsState();
}

class _MailSettingsState extends State<MailSettings> {
  final _storage = const FlutterSecureStorage();
  final _dio = Dio(BaseOptions(baseUrl: AppConfig.apiUrl));

  final _sigCtrl = TextEditingController();
  final _replyToCtrl = TextEditingController();
  bool _autoLoadImages = true, _htmlEnabled = true, _markReadOnOpen = true, _archiveOnSwipe = false;
  int _checkIntervalMin = 15;

  // Внешний IMAP
  bool _imapEnabled = false;
  final _imapHostCtrl = TextEditingController();
  final _imapPortCtrl = TextEditingController(text: '993');
  bool _imapSsl = true;
  final _imapUserCtrl = TextEditingController();
  final _imapPassCtrl = TextEditingController();

  // Внешний SMTP
  bool _smtpEnabled = false;
  final _smtpHostCtrl = TextEditingController();
  final _smtpPortCtrl = TextEditingController(text: '587');
  bool _smtpSsl = true;
  final _smtpUserCtrl = TextEditingController();
  final _smtpPassCtrl = TextEditingController();

  bool _loading = false;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final t = await _storage.read(key: 'access_token');
    if (t != null) _dio.options.headers['Authorization'] = 'Bearer $t';
    try {
      final r = await _dio.get('/settings');
      final m = ((r.data['settings']['mail']) as Map?) ?? {};
      setState(() {
        _sigCtrl.text = m['signature'] ?? '';
        _replyToCtrl.text = m['replyTo'] ?? '';
        _autoLoadImages = m['autoLoadImages'] == true;
        _htmlEnabled = m['htmlEnabled'] == true;
        _markReadOnOpen = m['markReadOnOpen'] == true;
        _archiveOnSwipe = m['archiveOnSwipe'] == true;
        _checkIntervalMin = m['checkIntervalMin'] ?? 15;
        final imap = m['externalImap'] as Map<String, dynamic>? ?? {};
        _imapEnabled = imap['enabled'] == true;
        _imapHostCtrl.text = imap['host'] ?? '';
        _imapPortCtrl.text = (imap['port'] ?? 993).toString();
        _imapSsl = imap['ssl'] == true;
        _imapUserCtrl.text = imap['user'] ?? '';
        final smtp = m['externalSmtp'] as Map<String, dynamic>? ?? {};
        _smtpEnabled = smtp['enabled'] == true;
        _smtpHostCtrl.text = smtp['host'] ?? '';
        _smtpPortCtrl.text = (smtp['port'] ?? 587).toString();
        _smtpSsl = smtp['ssl'] == true;
        _smtpUserCtrl.text = smtp['user'] ?? '';
      });
    } catch (_) {}
  }

  Future<void> _save() async {
    setState(() => _loading = true);
    try {
      await _dio.patch('/settings/mail', data: {
        'signature': _sigCtrl.text,
        'replyTo': _replyToCtrl.text.trim(),
        'autoLoadImages': _autoLoadImages,
        'htmlEnabled': _htmlEnabled,
        'markReadOnOpen': _markReadOnOpen,
        'archiveOnSwipe': _archiveOnSwipe,
        'checkIntervalMin': _checkIntervalMin,
        'externalImap': {
          'enabled': _imapEnabled, 'host': _imapHostCtrl.text.trim(),
          'port': int.tryParse(_imapPortCtrl.text) ?? 993, 'ssl': _imapSsl,
          'user': _imapUserCtrl.text.trim(), 'password': _imapPassCtrl.text,
        },
        'externalSmtp': {
          'enabled': _smtpEnabled, 'host': _smtpHostCtrl.text.trim(),
          'port': int.tryParse(_smtpPortCtrl.text) ?? 587, 'ssl': _smtpSsl,
          'user': _smtpUserCtrl.text.trim(), 'password': _smtpPassCtrl.text,
        },
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Настройки почты сохранены'), backgroundColor: Colors.green));
    } catch (_) {} finally { setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройки почты'),
        actions: [TextButton(
          onPressed: _loading ? null : _save,
          child: const Text('Сохранить', style: TextStyle(color: Color(0xFF2AABEE), fontWeight: FontWeight.w600)),
        )],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [

        _Sec('Основные'),
        _field('Подпись', _sigCtrl, maxLines: 3),
        const SizedBox(height: 12),
        _field('Reply-To адрес', _replyToCtrl, hint: 'email@example.com'),
        const SizedBox(height: 12),

        _Sec('Отображение'),
        SwitchListTile(title: const Text('Загружать изображения автоматически'), value: _autoLoadImages,
            onChanged: (v) => setState(() => _autoLoadImages = v), activeColor: const Color(0xFF2AABEE), contentPadding: EdgeInsets.zero),
        SwitchListTile(title: const Text('Поддержка HTML-писем'), value: _htmlEnabled,
            onChanged: (v) => setState(() => _htmlEnabled = v), activeColor: const Color(0xFF2AABEE), contentPadding: EdgeInsets.zero),
        SwitchListTile(title: const Text('Отмечать прочитанным при открытии'), value: _markReadOnOpen,
            onChanged: (v) => setState(() => _markReadOnOpen = v), activeColor: const Color(0xFF2AABEE), contentPadding: EdgeInsets.zero),
        SwitchListTile(title: const Text('Архивировать при свайпе'), value: _archiveOnSwipe,
            onChanged: (v) => setState(() => _archiveOnSwipe = v), activeColor: const Color(0xFF2AABEE), contentPadding: EdgeInsets.zero),

        const SizedBox(height: 12),
        const Text('Проверять почту каждые', style: TextStyle(fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          value: _checkIntervalMin,
          decoration: InputDecoration(filled: true, fillColor: const Color(0xFFF5F5F5),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none)),
          items: const [
            DropdownMenuItem(value: 0, child: Text('Только push-уведомления')),
            DropdownMenuItem(value: 5, child: Text('5 минут')),
            DropdownMenuItem(value: 15, child: Text('15 минут')),
            DropdownMenuItem(value: 30, child: Text('30 минут')),
            DropdownMenuItem(value: 60, child: Text('1 час')),
          ],
          onChanged: (v) => setState(() => _checkIntervalMin = v ?? 15),
        ),

        const SizedBox(height: 24),
        _Sec('Внешний IMAP (Gmail, Outlook, Mail.ru...)'),
        SwitchListTile(title: const Text('Включить IMAP'), value: _imapEnabled,
            onChanged: (v) => setState(() => _imapEnabled = v), activeColor: const Color(0xFF2AABEE), contentPadding: EdgeInsets.zero),
        if (_imapEnabled) ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(flex: 3, child: _field('IMAP сервер', _imapHostCtrl, hint: 'imap.gmail.com')),
            const SizedBox(width: 10),
            Expanded(child: _field('Порт', _imapPortCtrl, hint: '993', type: TextInputType.number)),
          ]),
          const SizedBox(height: 10),
          SwitchListTile(title: const Text('SSL/TLS'), value: _imapSsl,
              onChanged: (v) => setState(() => _imapSsl = v), activeColor: const Color(0xFF2AABEE), contentPadding: EdgeInsets.zero),
          _field('Email', _imapUserCtrl, hint: 'user@gmail.com', type: TextInputType.emailAddress),
          const SizedBox(height: 10),
          _field('Пароль или App Password', _imapPassCtrl, obscure: true),
        ],

        const SizedBox(height: 24),
        _Sec('Внешний SMTP (отправка)'),
        SwitchListTile(title: const Text('Включить SMTP'), value: _smtpEnabled,
            onChanged: (v) => setState(() => _smtpEnabled = v), activeColor: const Color(0xFF2AABEE), contentPadding: EdgeInsets.zero),
        if (_smtpEnabled) ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(flex: 3, child: _field('SMTP сервер', _smtpHostCtrl, hint: 'smtp.gmail.com')),
            const SizedBox(width: 10),
            Expanded(child: _field('Порт', _smtpPortCtrl, hint: '587', type: TextInputType.number)),
          ]),
          const SizedBox(height: 10),
          SwitchListTile(title: const Text('SSL/TLS'), value: _smtpSsl,
              onChanged: (v) => setState(() => _smtpSsl = v), activeColor: const Color(0xFF2AABEE), contentPadding: EdgeInsets.zero),
          _field('Email', _smtpUserCtrl, hint: 'user@gmail.com', type: TextInputType.emailAddress),
          const SizedBox(height: 10),
          _field('Пароль', _smtpPassCtrl, obscure: true),
        ],

        const SizedBox(height: 40),
      ]),
    );
  }

  Widget _Sec(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 4),
    child: Text(t, style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1)),
  );

  Widget _field(String label, TextEditingController ctrl,
      {int maxLines = 1, String? hint, bool obscure = false, TextInputType type = TextInputType.text}) {
    return TextField(
      controller: ctrl, maxLines: maxLines, obscureText: obscure, keyboardType: type,
      decoration: InputDecoration(
        labelText: label, hintText: hint,
        filled: true, fillColor: const Color(0xFFF5F5F5),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  @override
  void dispose() {
    for (final c in [_sigCtrl,_replyToCtrl,_imapHostCtrl,_imapPortCtrl,_imapUserCtrl,_imapPassCtrl,
                     _smtpHostCtrl,_smtpPortCtrl,_smtpUserCtrl,_smtpPassCtrl]) c.dispose();
    super.dispose();
  }
}

