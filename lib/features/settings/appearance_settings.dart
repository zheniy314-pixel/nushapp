import 'package:flutter/material.dart';

class AppearanceSettings extends StatefulWidget {
  const AppearanceSettings({super.key});
  @override State<AppearanceSettings> createState() => _AppearanceSettingsState();
}

class _AppearanceSettingsState extends State<AppearanceSettings> {
  String _theme = 'system';
  double _fontSize = 15;
  String _accentColor = '#2AABEE';
  bool _animations = true, _sendByEnter = false;

  static const _colors = [
    {'name': 'Синий (Telegram)', 'hex': '#2AABEE', 'color': Color(0xFF2AABEE)},
    {'name': 'Зелёный', 'hex': '#4CAF50', 'color': Color(0xFF4CAF50)},
    {'name': 'Фиолетовый', 'hex': '#9C27B0', 'color': Color(0xFF9C27B0)},
    {'name': 'Оранжевый', 'hex': '#FF9800', 'color': Color(0xFFFF9800)},
    {'name': 'Красный', 'hex': '#F44336', 'color': Color(0xFFF44336)},
    {'name': 'Розовый', 'hex': '#E91E63', 'color': Color(0xFFE91E63)},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Оформление')),
      body: ListView(padding: const EdgeInsets.all(16), children: [

        _Sec('Тема'),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'light', icon: Icon(Icons.light_mode), label: Text('Светлая')),
            ButtonSegment(value: 'system', icon: Icon(Icons.brightness_auto), label: Text('Авто')),
            ButtonSegment(value: 'dark', icon: Icon(Icons.dark_mode), label: Text('Тёмная')),
          ],
          selected: {_theme},
          onSelectionChanged: (s) => setState(() => _theme = s.first),
          style: ButtonStyle(backgroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected) ? const Color(0xFF2AABEE) : null)),
        ),

        const SizedBox(height: 24),
        _Sec('Акцентный цвет'),
        Wrap(spacing: 12, runSpacing: 12, children: _colors.map((c) {
          final selected = _accentColor == c['hex'];
          return GestureDetector(
            onTap: () => setState(() => _accentColor = c['hex'] as String),
            child: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: c['color'] as Color,
                shape: BoxShape.circle,
                border: Border.all(color: selected ? Colors.black : Colors.transparent, width: 3),
              ),
              child: selected ? const Icon(Icons.check, color: Colors.white) : null,
            ),
          );
        }).toList()),

        const SizedBox(height: 24),
        _Sec('Размер шрифта — ${_fontSize.round()}'),
        Row(children: [
          const Text('A', style: TextStyle(fontSize: 12)),
          Expanded(child: Slider(
            value: _fontSize, min: 12, max: 20, divisions: 8,
            activeColor: const Color(0xFF2AABEE),
            onChanged: (v) => setState(() => _fontSize = v),
          )),
          const Text('A', style: TextStyle(fontSize: 20)),
        ]),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(12)),
          child: Text('Пример текста сообщения в чате',
              style: TextStyle(fontSize: _fontSize)),
        ),

        const SizedBox(height: 24),
        _Sec('Дополнительно'),
        SwitchListTile(
          title: const Text('Анимации интерфейса'),
          value: _animations, onChanged: (v) => setState(() => _animations = v),
          activeColor: const Color(0xFF2AABEE), contentPadding: EdgeInsets.zero,
        ),
        SwitchListTile(
          title: const Text('Enter отправляет сообщение'),
          subtitle: const Text('Только для внешней клавиатуры', style: TextStyle(fontSize: 12)),
          value: _sendByEnter, onChanged: (v) => setState(() => _sendByEnter = v),
          activeColor: const Color(0xFF2AABEE), contentPadding: EdgeInsets.zero,
        ),
      ]),
    );
  }

  Widget _Sec(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 10, top: 4),
    child: Text(t, style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1)),
  );
}
