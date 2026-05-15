import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:purevideo/core/services/settings_service.dart';
import 'package:purevideo/di/injection_container.dart';

class CastProxyDialog extends StatefulWidget {
  const CastProxyDialog({super.key});

  @override
  State<CastProxyDialog> createState() => _CastProxyDialogState();
}

class _CastProxyDialogState extends State<CastProxyDialog> {
  late final TextEditingController _proxyController;
  late final TextEditingController _receiverIdController;
  late final String _initialReceiverId;
  final SettingsService _settings = getIt();
  final Dio _dio = getIt();

  bool _testing = false;
  bool _saving = false;
  String? _testMessage;
  bool? _testOk;

  @override
  void initState() {
    super.initState();
    _proxyController = TextEditingController(text: _settings.castProxyUrl);
    _initialReceiverId = _settings.castReceiverAppId;
    _receiverIdController = TextEditingController(text: _initialReceiverId);
  }

  @override
  void dispose() {
    _proxyController.dispose();
    _receiverIdController.dispose();
    super.dispose();
  }

  String? _validateProxy(String value) {
    final v = value.trim();
    if (v.isEmpty) return null; // pusty adres jest OK (proxy wylaczone)
    final uri = Uri.tryParse(v);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return 'Nieprawidlowy adres. Przyklad: http://192.168.1.42:8080';
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return 'Adres musi zaczynac sie od http:// lub https://';
    }
    return null;
  }

  String? _validateReceiverId(String value) {
    final v = value.trim();
    if (v.isEmpty) return null; // puste = przywroc default
    // Application ID Google Cast: zwykle 8 znakow hex, ale nie wymuszamy
    // sztywno - zostawiamy luz na ewentualne zmiany formatu.
    if (!RegExp(r'^[A-Za-z0-9]+$').hasMatch(v)) {
      return 'ID moze zawierac tylko litery i cyfry';
    }
    if (v.length < 4 || v.length > 16) {
      return 'ID powinno miec 4-16 znakow';
    }
    return null;
  }

  Future<void> _onTest() async {
    final v = _proxyController.text.trim();
    final err = _validateProxy(v);
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
        _testMessage = 'Pole proxy puste - cast bezposrednio';
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
            ? 'Polaczenie OK (${response.statusCode})'
            : 'Odpowiedz: ${response.statusCode} ${body.isEmpty ? '' : '- $body'}';
      });
    } catch (e) {
      setState(() {
        _testing = false;
        _testOk = false;
        _testMessage = 'Brak polaczenia: ${_shortError(e)}';
      });
    }
  }

  String _shortError(Object e) {
    final s = e.toString();
    if (s.length > 120) return '${s.substring(0, 120)}...';
    return s;
  }

  Future<void> _onSave() async {
    final proxy = _proxyController.text.trim();
    final proxyErr = _validateProxy(proxy);
    if (proxyErr != null) {
      setState(() {
        _testOk = false;
        _testMessage = proxyErr;
      });
      return;
    }

    final rawId = _receiverIdController.text.trim();
    final idErr = _validateReceiverId(rawId);
    if (idErr != null) {
      setState(() {
        _testOk = false;
        _testMessage = idErr;
      });
      return;
    }

    setState(() => _saving = true);

    final newId = rawId.toUpperCase();
    final receiverChanged = newId != _initialReceiverId.toUpperCase();

    _settings.setCastProxyUrl(proxy);
    await _settings.setCastReceiverAppId(rawId);

    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop();

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(receiverChanged
            ? 'Zapisano. Zrestartuj aplikacje aby zastosowac nowy receiver Cast.'
            : (proxy.isEmpty
                ? 'Proxy Cast wylaczone'
                : 'Zapisano ustawienia Cast')),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: receiverChanged ? 5 : 2),
      ),
    );
  }

  void _resetReceiverIdToDefault() {
    setState(() {
      _receiverIdController.text = SettingsService.defaultCastReceiverAppId;
      _testOk = null;
      _testMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final busy = _testing || _saving;

    Color? statusColor;
    IconData? statusIcon;
    if (_testOk == true) {
      statusColor = Colors.green;
      statusIcon = Icons.check_circle_outline;
    } else if (_testOk == false) {
      statusColor = cs.error;
      statusIcon = Icons.error_outline;
    }

    final receiverChanged = _receiverIdController.text.trim().toUpperCase() !=
        _initialReceiverId.toUpperCase();

    return AlertDialog(
      title: const Text('Ustawienia Cast'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Adres proxy', style: tt.titleSmall),
            const SizedBox(height: 4),
            Text(
              'Adres serwera proxy uruchomionego w Twojej sieci '
              '(katalog proxy/ w repo). Pozostaw puste aby castowac '
              'bezposrednio.',
              style: tt.bodySmall?.copyWith(
                color: cs.onSurface.withAlpha(179),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _proxyController,
              autocorrect: false,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: 'Adres proxy',
                hintText: 'http://192.168.1.42:8080',
                border: const OutlineInputBorder(),
                suffixIcon: _proxyController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            _proxyController.clear();
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
            const SizedBox(height: 24),
            Text('Application ID receivera', style: tt.titleSmall),
            const SizedBox(height: 4),
            Text(
              'ID Cast Receivera (8 znakow hex). Default '
              '"${SettingsService.defaultCastReceiverAppId}" = oficjalny '
              'Default Media Receiver Google. Mozna wpisac ID wlasnego '
              'custom receivera (np. z shaka-playerem dla fMP4-in-HLS).',
              style: tt.bodySmall?.copyWith(
                color: cs.onSurface.withAlpha(179),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _receiverIdController,
              autocorrect: false,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                LengthLimitingTextInputFormatter(16),
              ],
              decoration: InputDecoration(
                labelText: 'Application ID',
                hintText: SettingsService.defaultCastReceiverAppId,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: 'Przywroc domyslny',
                  icon: const Icon(Icons.restore),
                  onPressed: _resetReceiverIdToDefault,
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (receiverChanged) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_outlined,
                      size: 18, color: cs.tertiary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Zmiana ID wymaga ponownego uruchomienia aplikacji.',
                      style: tt.bodySmall?.copyWith(color: cs.tertiary),
                    ),
                  ),
                ],
              ),
            ],
            if (_testMessage != null) ...[
              const SizedBox(height: 16),
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
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Anuluj'),
        ),
        TextButton(
          onPressed: busy ? null : _onTest,
          child: _testing
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Testuj proxy'),
        ),
        FilledButton(
          onPressed: busy ? null : _onSave,
          child: _saving
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Zapisz'),
        ),
      ],
    );
  }
}
