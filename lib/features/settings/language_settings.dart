import 'package:flutter/material.dart';

class LanguageSettings extends StatefulWidget {
  const LanguageSettings({super.key});
  @override State<LanguageSettings> createState() => _LanguageSettingsState();
}

class _LanguageSettingsState extends State<LanguageSettings> {
  String _lang = 'ru';
  bool _use24h = true;

  static const _langs = [
    {'code': 'ru', 'name': 'Русский', 'native': 'Русский'},
    {'code': 'en', 'name': 'English', 'native': 'English'},
    {'code': 'uk', 'name': 'Українська', 'native': 'Українська'},
    {'code': 'de', 'name': 'Deutsch', 'native': 'Deutsch'},
    {'code': 'fr', 'name': 'Français', 'native': 'Français'},
    {'code': 'zh', 'name': 'Китайский', 'native': '中文'},
    {'code': 'ar', 'name': 'Арабский', 'native': 'العربية'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Язык и регион')),
      body: ListView(children: [
        ..._langs.map((l) => RadioListTile<String>(
          title: Text(l['native']!),
          subtitle: Text(l['name']!),
          value: l['code']!, groupValue: _lang,
          onChanged: (v) => setState(() => _lang = v ?? 'ru'),
          activeColor: const Color(0xFF2AABEE),
        )),
        const Divider(),
        SwitchListTile(
          title: const Text('24-часовой формат времени'),
          value: _use24h, onChanged: (v) => setState(() => _use24h = v),
          activeColor: const Color(0xFF2AABEE),
        ),
      ]),
    );
  }
}
