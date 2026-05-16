import 'package:flutter/material.dart';

class SecuritySettings extends StatefulWidget {
  const SecuritySettings({super.key});
  @override State<SecuritySettings> createState() => _SecuritySettingsState();
}

class _SecuritySettingsState extends State<SecuritySettings> {
  bool _biometric = false, _screenshot = true, _secretMode = false, _twoFactor = false;
  int _autoLock = 0;
  int _clipboardClear = 60;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Пароль и безопасность')),
      body: ListView(children: [
        _Sec('Вход'),
        ListTile(leading: const Icon(Icons.fingerprint, color: Color(0xFF2AABEE)),
          title: const Text('Вход по биометрии'), subtitle: const Text('Face ID / Fingerprint'),
          trailing: Switch(value: _biometric, onChanged: (v) => setState(() => _biometric = v), activeColor: const Color(0xFF2AABEE))),
        ListTile(leading: const Icon(Icons.lock_outline, color: Color(0xFF2AABEE)),
          title: const Text('Автоблокировка'),
          trailing: DropdownButton<int>(
            value: _autoLock, underline: const SizedBox(),
            items: const [
              DropdownMenuItem(value: 0, child: Text('Никогда')),
              DropdownMenuItem(value: 1, child: Text('1 мин')),
              DropdownMenuItem(value: 5, child: Text('5 мин')),
              DropdownMenuItem(value: 15, child: Text('15 мин')),
              DropdownMenuItem(value: 60, child: Text('1 час')),
            ],
            onChanged: (v) => setState(() => _autoLock = v ?? 0),
          )),

        const Divider(),
        _Sec('Приватность'),
        SwitchListTile(title: const Text('Защита от скриншотов'),
          subtitle: const Text('Блокирует скриншоты в мессенджере', style: TextStyle(fontSize: 12)),
          value: _screenshot, onChanged: (v) => setState(() => _screenshot = v), activeColor: const Color(0xFF2AABEE)),
        SwitchListTile(title: const Text('Секретный режим'),
          subtitle: const Text('Все чаты — с автоудалением сообщений', style: TextStyle(fontSize: 12)),
          value: _secretMode, onChanged: (v) => setState(() => _secretMode = v), activeColor: const Color(0xFF2AABEE)),
        ListTile(title: const Text('Очистить буфер обмена'),
          subtitle: Text(_clipboardClear == 0 ? 'Не очищать' : 'Через $_clipboardClear сек'),
          trailing: DropdownButton<int>(
            value: _clipboardClear, underline: const SizedBox(),
            items: const [
              DropdownMenuItem(value: 0, child: Text('Не очищать')),
              DropdownMenuItem(value: 30, child: Text('30 сек')),
              DropdownMenuItem(value: 60, child: Text('1 мин')),
              DropdownMenuItem(value: 180, child: Text('3 мин')),
            ],
            onChanged: (v) => setState(() => _clipboardClear = v ?? 60),
          )),

        const Divider(),
        _Sec('Дополнительно'),
        SwitchListTile(title: const Text('Двухфакторная аутентификация'),
          subtitle: const Text('Пароль при каждом новом входе', style: TextStyle(fontSize: 12)),
          value: _twoFactor, onChanged: (v) => setState(() => _twoFactor = v), activeColor: const Color(0xFF2AABEE)),
        ListTile(leading: const Icon(Icons.delete_forever, color: Colors.red),
          title: const Text('Завершить все сессии', style: TextStyle(color: Colors.red)),
          onTap: () {}),
      ]),
    );
  }

  Widget _Sec(String t) => Padding(
    padding: const EdgeInsets.only(left: 16, top: 16, bottom: 4),
    child: Text(t.toUpperCase(), style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1)),
  );
}
