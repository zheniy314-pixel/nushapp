import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/services/background_service.dart';
import '../../core/services/global_notif_listener.dart';
import '../auth/auth_screen.dart';
import '../chats/main_screen.dart';

class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen>
    with WidgetsBindingObserver {
  final _storage = const FlutterSecureStorage();

  String _display = '0';
  String _input = '';
  String? _operator;
  double? _firstOperand;
  bool _shouldReset = false;

  // Tracks if messenger was opened in this session (PIN required again on resume)
  static bool _messengerWasOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // Reset display on return to calculator
    _display = '0';
    _input = '';
    _messengerWasOpen = false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When app goes to background while messenger is open → will require PIN on resume
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      if (_messengerWasOpen) {
        // Will be reset when user comes back — handled by MainScreen returning to calculator
      }
    }
    if (state == AppLifecycleState.resumed && _messengerWasOpen) {
      // Pop back to calculator on resume
      if (mounted) {
        Navigator.of(context).popUntil((r) => r.isFirst);
        setState(() { _display = '0'; _input = ''; _messengerWasOpen = false; });
      }
    }
  }

  void _onButton(String value) {
    setState(() {
      if (value == 'AC') {
        _display = '0'; _input = ''; _operator = null; _firstOperand = null;
        return;
      }
      if (value == '=') {
        _handleEquals();
        return;
      }
      if (['+', '−', '×', '÷'].contains(value)) {
        _handleOperator(value);
        return;
      }
      if (value == '+/−') {
        if (_input.startsWith('-')) { _input = _input.substring(1); }
        else if (_input != '0' && _input.isNotEmpty) { _input = '-$_input'; }
        _display = _input.isEmpty ? '0' : _input;
        return;
      }
      if (value == '%') {
        final v = double.tryParse(_input) ?? 0;
        _input = (v / 100).toString().replaceAll(RegExp(r'\.?0+$'), '');
        _display = _input;
        return;
      }
      if (_shouldReset) { _input = ''; _shouldReset = false; }
      if (value == '.' && _input.contains('.')) return;
      if (value == '.' && _input.isEmpty) { _input = '0'; }
      if (_input == '0' && value != '.') { _input = value; }
      else { _input += value; }
      _display = _input;
    });
  }

  void _handleOperator(String op) {
    _firstOperand = double.tryParse(_input) ?? _firstOperand;
    _operator = op;
    _shouldReset = true;
    _display = _input.isEmpty ? '0' : _input;
  }

  Future<void> _handleEquals() async {
    final secretPin = await _storage.read(key: 'secret_pin') ?? '1337';
    final panicPin  = await _storage.read(key: 'panic_pin')  ?? '9999';
    final token     = await _storage.read(key: 'access_token');

    if (_input == panicPin) {
      await _panicWipe();
      return;
    }
    if (_input == secretPin) {
      if (token != null && token.isNotEmpty) {
        final userId = await _storage.read(key: 'user_id') ?? '';
        // Update global notification listener so it doesn't self-notify
        GlobalNotifListener().updateUserId(userId);
        notifyBackgroundServiceLogin(token: token, userId: userId);
      }
      _openMessenger(token);
      setState(() { _display = '0'; _input = ''; });
      return;
    }

    if (_firstOperand == null || _operator == null) {
      _display = _input.isEmpty ? '0' : _input;
      return;
    }
    final second = double.tryParse(_input) ?? 0;
    double result;
    switch (_operator) {
      case '+': result = _firstOperand! + second; break;
      case '−': result = _firstOperand! - second; break;
      case '×': result = _firstOperand! * second; break;
      case '÷': result = second != 0 ? _firstOperand! / second : double.nan; break;
      default:  result = second;
    }
    final r = result.isNaN
        ? 'Ошибка'
        : (result == result.toInt()
            ? result.toInt().toString()
            : result.toStringAsFixed(8).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), ''));
    setState(() {
      _display = r; _input = r;
      _firstOperand = null; _operator = null; _shouldReset = true;
    });
  }

  void _openMessenger(String? token) {
    _messengerWasOpen = true;
    if (!mounted) return;
    if (token != null && token.isNotEmpty) {
      Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const MainScreen(),
          transitionDuration: Duration.zero,
        ),
      );
    } else {
      Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const AuthScreen(),
          transitionDuration: Duration.zero,
        ),
      );
    }
  }

  Future<void> _panicWipe() async {
    await _storage.deleteAll();
    setState(() { _display = '0'; _input = ''; });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Данные очищены'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor     = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final btnColorNum  = isDark ? const Color(0xFF3A3A3C) : const Color(0xFFD4D4D2);
    final btnColorOp   = const Color(0xFF2AABEE);
    final btnColorFunc = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFA5A5A5);

    return PopScope(
      canPop: false,   // Нельзя вернуться из калькулятора системной кнопкой
      child: Scaffold(
        backgroundColor: bgColor,
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                flex: 2,
                child: Container(
                  alignment: Alignment.bottomRight,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Text(
                    _display,
                    style: TextStyle(
                      fontSize: _display.length > 9 ? 40 : 64,
                      fontWeight: FontWeight.w300,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              Expanded(
                flex: 5,
                child: GridView.count(
                  crossAxisCount: 4,
                  childAspectRatio: 1.0,
                  padding: const EdgeInsets.all(12),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _btn('AC',  btnColorFunc, Colors.black),
                    _btn('+/−', btnColorFunc, Colors.black),
                    _btn('%',   btnColorFunc, Colors.black),
                    _btn('÷',   btnColorOp,  Colors.white),
                    _btn('7',   btnColorNum, isDark ? Colors.white : Colors.black),
                    _btn('8',   btnColorNum, isDark ? Colors.white : Colors.black),
                    _btn('9',   btnColorNum, isDark ? Colors.white : Colors.black),
                    _btn('×',   btnColorOp,  Colors.white),
                    _btn('4',   btnColorNum, isDark ? Colors.white : Colors.black),
                    _btn('5',   btnColorNum, isDark ? Colors.white : Colors.black),
                    _btn('6',   btnColorNum, isDark ? Colors.white : Colors.black),
                    _btn('−',   btnColorOp,  Colors.white),
                    _btn('1',   btnColorNum, isDark ? Colors.white : Colors.black),
                    _btn('2',   btnColorNum, isDark ? Colors.white : Colors.black),
                    _btn('3',   btnColorNum, isDark ? Colors.white : Colors.black),
                    _btn('+',   btnColorOp,  Colors.white),
                    _btn('.',   btnColorNum, isDark ? Colors.white : Colors.black),
                    _btn('0',   btnColorNum, isDark ? Colors.white : Colors.black),
                    _btn('⌫',   btnColorNum, isDark ? Colors.white : Colors.black),
                    _btn('=',   btnColorOp,  Colors.white),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _btn(String label, Color bg, Color fg) {
    return GestureDetector(
      onTap: () {
        if (label == '⌫') {
          setState(() {
            if (_input.isNotEmpty) { _input = _input.substring(0, _input.length - 1); }
            _display = _input.isEmpty ? '0' : _input;
          });
        } else {
          _onButton(label);
        }
      },
      child: Container(
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Text(label, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w400, color: fg)),
      ),
    );
  }
}
