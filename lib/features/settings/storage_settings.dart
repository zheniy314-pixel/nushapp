import 'package:flutter/material.dart';

class StorageSettings extends StatefulWidget {
  const StorageSettings({super.key});
  @override State<StorageSettings> createState() => _StorageSettingsState();
}

class _StorageSettingsState extends State<StorageSettings> {
  String _photoDownload = 'wifi', _videoDownload = 'wifi', _fileDownload = 'never';
  bool _saveToGallery = true, _autoPlayGifs = true, _autoPlayVideo = false;
  int _cacheLimit = 1024;

  static const _opts = ['wifi', 'always', 'never'];
  static const _optLabels = ['По WiFi', 'Всегда', 'Никогда'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Данные и хранилище')),
      body: ListView(children: [
        _Sec('Автозагрузка'),
        _DropRow('Фото', _photoDownload, (v) => setState(() => _photoDownload = v)),
        _DropRow('Видео', _videoDownload, (v) => setState(() => _videoDownload = v)),
        _DropRow('Файлы', _fileDownload, (v) => setState(() => _fileDownload = v)),
        const Divider(),
        _Sec('Медиа'),
        SwitchListTile(title: const Text('Сохранять в галерею'), value: _saveToGallery,
          onChanged: (v) => setState(() => _saveToGallery = v), activeColor: const Color(0xFF2AABEE)),
        SwitchListTile(title: const Text('Автовоспроизведение GIF'), value: _autoPlayGifs,
          onChanged: (v) => setState(() => _autoPlayGifs = v), activeColor: const Color(0xFF2AABEE)),
        SwitchListTile(title: const Text('Автовоспроизведение видео'), value: _autoPlayVideo,
          onChanged: (v) => setState(() => _autoPlayVideo = v), activeColor: const Color(0xFF2AABEE)),
        const Divider(),
        _Sec('Кеш'),
        ListTile(title: const Text('Лимит кеша'),
          subtitle: Text(_cacheLimit == 0 ? 'Без ограничений' : '$_cacheLimit МБ'),
          trailing: DropdownButton<int>(value: _cacheLimit, underline: const SizedBox(),
            items: const [
              DropdownMenuItem(value: 0, child: Text('Нет')),
              DropdownMenuItem(value: 512, child: Text('512 МБ')),
              DropdownMenuItem(value: 1024, child: Text('1 ГБ')),
              DropdownMenuItem(value: 2048, child: Text('2 ГБ')),
              DropdownMenuItem(value: 5120, child: Text('5 ГБ')),
            ],
            onChanged: (v) => setState(() => _cacheLimit = v ?? 1024))),
        ListTile(leading: const Icon(Icons.delete_outline, color: Colors.red),
          title: const Text('Очистить кеш', style: TextStyle(color: Colors.red)),
          subtitle: const Text('Освободит место, медиа не удалятся'),
          onTap: () {}),
      ]),
    );
  }

  Widget _Sec(String t) => Padding(padding: const EdgeInsets.only(left: 16, top: 16, bottom: 4),
    child: Text(t.toUpperCase(), style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1)));

  Widget _DropRow(String title, String val, Function(String) onChanged) => ListTile(
    title: Text(title),
    trailing: DropdownButton<String>(value: val, underline: const SizedBox(),
      items: List.generate(_opts.length, (i) => DropdownMenuItem(value: _opts[i], child: Text(_optLabels[i]))),
      onChanged: (v) => v != null ? onChanged(v) : null));
}
