import 'package:flutter/material.dart';

class OfflineSettings extends StatefulWidget {
  const OfflineSettings({super.key});
  @override State<OfflineSettings> createState() => _OfflineSettingsState();
}

class _OfflineSettingsState extends State<OfflineSettings> {
  bool _bt = true, _wifi = true, _sms = false, _relay = false;
  final _phoneCtrl = TextEditingController();
  int _retentionHours = 72;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Офлайн-доставка')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Container(padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: const Color(0xFF2AABEE).withOpacity(0.08), borderRadius: BorderRadius.circular(12)),
          child: const Text(
            'Когда интернет недоступен, Нуша пытается доставить сообщения '
            'через Bluetooth, WiFi Direct или SMS. Сообщения всегда зашифрованы.',
            style: TextStyle(fontSize: 13, height: 1.5),
          )),
        const SizedBox(height: 24),
        _Sec('Каналы доставки'),
        SwitchListTile(
          title: const Text('Bluetooth'), subtitle: const Text('Короткий радиус, низкое потребление', style: TextStyle(fontSize: 12)),
          secondary: const Icon(Icons.bluetooth, color: Color(0xFF2AABEE)),
          value: _bt, onChanged: (v) => setState(() => _bt = v), activeColor: const Color(0xFF2AABEE), contentPadding: EdgeInsets.zero),
        SwitchListTile(
          title: const Text('WiFi Direct'), subtitle: const Text('До 200м без роутера, быстро', style: TextStyle(fontSize: 12)),
          secondary: const Icon(Icons.wifi_tethering, color: Colors.green),
          value: _wifi, onChanged: (v) => setState(() => _wifi = v), activeColor: const Color(0xFF2AABEE), contentPadding: EdgeInsets.zero),
        SwitchListTile(
          title: const Text('SMS-доставка'), subtitle: const Text('Зашифрованный текст, платно', style: TextStyle(fontSize: 12)),
          secondary: const Icon(Icons.sms_outlined, color: Colors.orange),
          value: _sms, onChanged: (v) => setState(() => _sms = v), activeColor: const Color(0xFF2AABEE), contentPadding: EdgeInsets.zero),
        if (_sms) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: 'Мой номер телефона (для SMS)', hintText: '+79001234567',
              filled: true, fillColor: const Color(0xFFF5F5F5),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
          ),
        ],
        const Divider(),
        _Sec('Mesh-сеть'),
        SwitchListTile(
          title: const Text('Быть relay-устройством'),
          subtitle: const Text('Помогать доставлять сообщения другим пользователям в зоне досягаемости', style: TextStyle(fontSize: 12)),
          secondary: const Icon(Icons.hub_outlined, color: Colors.purple),
          value: _relay, onChanged: (v) => setState(() => _relay = v), activeColor: const Color(0xFF2AABEE), contentPadding: EdgeInsets.zero),
        const Divider(),
        _Sec('Хранение'),
        ListTile(title: const Text('Хранить офлайн-пакеты'),
          subtitle: Text(_retentionHours == 24 ? '24 часа' : _retentionHours == 48 ? '48 часов' : '72 часа'),
          trailing: DropdownButton<int>(value: _retentionHours, underline: const SizedBox(),
            items: const [
              DropdownMenuItem(value: 24, child: Text('24 часа')),
              DropdownMenuItem(value: 48, child: Text('48 часов')),
              DropdownMenuItem(value: 72, child: Text('72 часа')),
            ],
            onChanged: (v) => setState(() => _retentionHours = v ?? 72)),
          contentPadding: EdgeInsets.zero),
      ]),
    );
  }

  Widget _Sec(String t) => Padding(padding: const EdgeInsets.only(bottom: 8, top: 4),
    child: Text(t.toUpperCase(), style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1)));

  @override void dispose() { _phoneCtrl.dispose(); super.dispose(); }
}
