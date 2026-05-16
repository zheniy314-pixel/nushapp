import 'package:flutter/material.dart';

class ContactsScreen extends StatelessWidget {
  const ContactsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Контакты'), actions: [
        IconButton(icon: const Icon(Icons.person_add_outlined), onPressed: () {}),
        IconButton(icon: const Icon(Icons.search), onPressed: () {}),
      ]),
      body: const Center(child: Text('Добавьте первый контакт', style: TextStyle(color: Color(0xFF8E8E93)))),
    );
  }
}
