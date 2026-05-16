import 'package:flutter/material.dart';

class StoriesScreen extends StatelessWidget {
  const StoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Истории')),
      body: const Center(child: Text('Нет активных историй', style: TextStyle(color: Color(0xFF8E8E93)))),
    );
  }
}
