import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:async';

/// Просмотр историй — Telegram-стиль (свайп вправо/влево)
class StoriesViewer extends StatefulWidget {
  final List<Map<String, dynamic>> stories;
  final int initialIndex;

  const StoriesViewer({super.key, required this.stories, this.initialIndex = 0});

  @override
  State<StoriesViewer> createState() => _StoriesViewerState();
}

class _StoriesViewerState extends State<StoriesViewer>
    with SingleTickerProviderStateMixin {
  late int _current;
  late AnimationController _progressCtrl;
  Timer? _autoTimer;

  static const _duration = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _progressCtrl = AnimationController(vsync: this, duration: _duration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _next();
      });
    _startProgress();
  }

  void _startProgress() {
    _progressCtrl.reset();
    _progressCtrl.forward();
  }

  void _next() {
    if (_current < widget.stories.length - 1) {
      setState(() => _current++);
      _startProgress();
    } else {
      Navigator.of(context).pop();
    }
  }

  void _prev() {
    if (_current > 0) {
      setState(() => _current--);
      _startProgress();
    }
  }

  @override
  void dispose() {
    _progressCtrl.dispose();
    _autoTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final story = widget.stories[_current];
    final mediaType = story['mediaType'] as String? ?? 'text';
    final mediaUrl  = story['mediaUrl'] as String?;
    final text      = story['textContent'] as String?;
    final bgColor   = _parseColor(story['bgColor'] as String? ?? '#000000');
    final authorName = story['authorName'] as String? ?? 'Пользователь';

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapDown: (d) {
          final x = d.localPosition.dx;
          final w = MediaQuery.of(context).size.width;
          if (x < w / 3) _prev();
          else if (x > 2 * w / 3) _next();
          // Центр — пауза/продолжить
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Фон / медиа
            if (mediaType == 'photo' && mediaUrl != null)
              CachedNetworkImage(imageUrl: mediaUrl, fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Container(color: bgColor))
            else
              Container(color: bgColor),

            // Текст поверх
            if (text != null && text.isNotEmpty)
              Center(child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(text,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 22,
                        fontWeight: FontWeight.w600, shadows: [Shadow(blurRadius: 8)])),
              )),

            // Градиент сверху и снизу
            Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Colors.black.withOpacity(0.4), Colors.transparent, Colors.black.withOpacity(0.3)],
                stops: const [0, 0.4, 1],
              ),
            ))),

            // Прогресс-бары
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: Row(
                      children: List.generate(widget.stories.length, (i) {
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: i < _current
                                  ? Container(height: 3, color: Colors.white)
                                  : i == _current
                                      ? AnimatedBuilder(
                                          animation: _progressCtrl,
                                          builder: (_, __) => LinearProgressIndicator(
                                            value: _progressCtrl.value,
                                            backgroundColor: Colors.white38,
                                            valueColor: const AlwaysStoppedAnimation(Colors.white),
                                            minHeight: 3,
                                          ),
                                        )
                                      : Container(height: 3, color: Colors.white38),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),

                  // Автор
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        const CircleAvatar(radius: 18, backgroundColor: Colors.white24,
                            child: Icon(Icons.person, color: Colors.white, size: 20)),
                        const SizedBox(width: 10),
                        Text(authorName,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _parseColor(String hex) {
    try {
      final h = hex.replaceAll('#', '');
      return Color(int.parse('FF$h', radix: 16));
    } catch (_) { return Colors.black; }
  }
}
