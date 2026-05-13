import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:purevideo/core/services/settings_service.dart';
import 'package:purevideo/di/injection_container.dart';

class CastProxyDialog extends StatefulWidget {
  const CastProxyDialog({super.key});

  @override
  State<CastProxyDialog> createState() => _CastProxyDialogState();
}

class _CastProxyDialogState extends State<CastProxyDialog> {
  late final TextEditingController _controller;
  final SettingsService _settings = getIt();
  final Dio _dio = getIt();

  bool _testing = false;
  String? _testMessage;
  bool? _testOk;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _settings.castProxyUrl);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _validate(String value) {
    final v = value.trim();
    if (v.isEmpty) return null; // pusty adres jest OK (proxy wyłączone)
    final uri = Uri.tryParse(v);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return 'Nieprawidłowy adres. Przykład: http://192.168.1.42:8080';
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return 'Adres musi zaczynać się od http:// lub https://';
    }
    return null;
  }

  Future<void> _onTest() async {
    final v = _controller.text.trim();
    final err = _validate(v);
    if (err != null) {
      setState(() {
        _testOk = false;
        _testMessage = err;
      });
      return;
    }
    if (v.isEmpty) {
      setState(() {
        _testOk = null;
        _testMessage = 'Pole puste - proxy wyłączone';
      });
      return;
    }

    setState(() {
      _testing = true;
      _testMessage = null;
      _testOk = null;
    });

    try {
      var base = v;
      while (base.endsWith('/')) {
        base = base.substring(0, base.length - 1);
      }
      final response = await _dio.get(
        '$base/health',
        options: Options(
          sendTimeout: const Duration(seconds: 4),
          receiveTimeout: const Duration(seconds: 4),
          validateStatus: (s) => true,
        ),
      );
      final body = response.data?.toString().trim() ?? '';
      final ok = response.statusCode == 200 && body == 'ok';
      setState(() {
        _testing = false;
        _testOk = ok;
        _testMessage = ok
            ? 'Połączenie OK (${response.statusCode})'
            : 'Odpowiedź: ${response.statusCode} ${body.isEmpty ? '' : '- $body'}';
      });
    } catch (e) {
      setState(() {
        _testing = false;
        _testOk = false;
        _testMessage = 'Brak połączenia: ${_shortError(e)}';
      });
    }
  }

  String _shortError(Object e) {
    final s = e.toString();
    if (s.length > 120) return '${s.substring(0, 120)}...';
    return s;
  }

  void _onSave() {
    final v = _controller.text.trim();
    final err = _validate(v);
    if (err != null) {
      setState(() {
        _testOk = false;
        _testMessage = err;
      });
      return;
    }
    _settings.setCastProxyUrl(v);
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(v.isEmpty
            ? 'Proxy Cast wyłączone'
            : 'Zapisano adres proxy Cast'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    Color? statusColor;
    IconData? statusIcon;
    if (_testOk == true) {
      statusColor = Colors.green;
      statusIcon = Icons.check_circle_outline;
    } else if (_testOk == false) {
      statusColor = cs.error;
      statusIcon = Icons.error_outline;
    }

    return AlertDialog(
      title: const Text('Adres proxy Cast'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Adres serwera proxy uruchomionego w Twojej sieci lokalnej '
            '(patrz katalog proxy/ w repo). Pozostaw puste, żeby castować '
            'bezpośrednio (bez nagłówków - może nie działać dla niektórych '
            'serwisów).',
            style: tt.bodySmall?.copyWith(
              color: cs.onSurface.withAlpha(179),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autocorrect: false,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: 'Adres proxy',
              hintText: 'http://192.168.1.42:8080',
              border: const OutlineInputBorder(),
              suffixIcon: _controller.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        setState(() {
                          _controller.clear();
                          _testOk = null;
                          _testMessage = null;
                        });
                      },
                    ),
            ),
            onChanged: (_) => setState(() {
              _testOk = null;
              _testMessage = null;
            }),
          ),
          if (_testMessage != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (statusIcon != null) ...[
                  Icon(statusIcon, size: 18, color: statusColor),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    _testMessage!,
                    style: tt.bodySmall?.copyWith(color: statusColor),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _testing ? null : () => Navigator.of(context).pop(),
          child: const Text('Anuluj'),
        ),
        TextButton(
          onPressed: _testing ? null : _onTest,
          child: _testing
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Testuj połączenie'),
        ),
        FilledButton(
          onPressed: _testing ? null : _onSave,
          child: const Text('Zapisz'),
        ),
      ],
    );
  }
}
