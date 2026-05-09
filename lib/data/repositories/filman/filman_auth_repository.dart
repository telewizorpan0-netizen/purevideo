import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:purevideo/core/services/webview_service.dart';
import 'package:purevideo/core/utils/supported_enum.dart';
import 'package:purevideo/data/models/account_model.dart';
import 'package:purevideo/data/models/auth_model.dart';
import 'package:purevideo/data/repositories/auth_repository.dart';
import 'package:purevideo/data/repositories/filman/filman_dio_factory.dart';
import 'package:purevideo/core/services/secure_storage_service.dart';
import 'package:purevideo/di/injection_container.dart';

class FilmanAuthRepository implements AuthRepository {
  late Dio _dio;
  AccountModel? _account;
  final _authController = StreamController<AuthModel>.broadcast();
  late StreamSubscription<AuthModel> _authSubscription;

  FilmanAuthRepository([AccountModel? account]) {
    _loadSavedAccount();
    _authSubscription = _authController.stream.listen(_onAuthChanged);
  }

  Future<void> _loadSavedAccount() async {
    try {
      final accountJson = await SecureStorageService.getServiceData(
        SupportedService.filman,
        'account',
      );

      if (accountJson != null) {
        _account = AccountModel.fromMap(jsonDecode(accountJson));
        _dio = FilmanDioFactory.getDio(_account);

        try {
          await _dio.get('/');
          _authController.add(
            AuthModel(
              service: SupportedService.filman,
              success: true,
              account: _account,
            ),
          );
        } catch (e) {
          await SecureStorageService.deleteServiceData(
            SupportedService.filman,
            'account',
          );
          _account = null;
          _dio = FilmanDioFactory.getDio(null);
        }
      } else {
        _dio = FilmanDioFactory.getDio(null);
      }
    } catch (e) {
      debugPrint('Błąd podczas ładowania konta Filman.cc: $e');
      _dio = FilmanDioFactory.getDio(null);
    }
  }

  void _onAuthChanged(AuthModel auth) {
    if (auth.service == SupportedService.filman) {
      _dio = FilmanDioFactory.getDio(auth.account);
    }
  }

  @override
  Stream<AuthModel> get authStream => _authController.stream;

  String _getFilmanLoginScript(String login, String password,
      {String? captcha}) {
    return '''
      (function() {
        function waitForElement(selector, callback) {
          const element = document.querySelector(selector);
          if (element) {
            callback(element);
          } else {
            setTimeout(() => waitForElement(selector, callback), 100);
          }
        }

        if (!window.location.href.includes('/logowanie')) {
          window.flutter_inappwebview.callHandler('messageHandler', JSON.stringify({success: true, cookies: document.cookie}));
          return;
        }

        waitForElement('.alert-danger', function(element) {
          window.flutter_inappwebview.callHandler('messageHandler', JSON.stringify({success: false, error: element.textContent.trim()}));
        });

        waitForElement('#signin-form', function(element) {
          element.login.value = '$login';
          element.password.value = '$password';
          ${captcha != null ? "if (document.getElementById('g-recaptcha-response')) { document.getElementById('g-recaptcha-response').value = '$captcha'; }" : ""}
          element.querySelector("button[name='submit']").click();
        });
      })();
    ''';
  }

  @override
  Future<AuthModel> signIn(
    Map<String, String> fields,
  ) async {
    try {
      final webviewLogin = await getIt<WebViewService>().executeJavaScript(
          '${SupportedService.filman.baseUrl}/logowanie',
          _getFilmanLoginScript(fields['login']!, fields['password']!,
              captcha: fields['g-recaptcha-response']));

      try {
        final json = jsonDecode(webviewLogin!);
        if (json['success'] == true && json['cookies'] != null) {
          final cookieList = (json['cookies'] as String).split(';');

          final cookies = cookieList
              .map((header) => Cookie.fromSetCookieValue(header))
              .toList();

          _account = AccountModel(
            fields: fields,
            cookies: cookies,
            service: SupportedService.filman,
          );

          final authModel = AuthModel(
            service: SupportedService.filman,
            success: true,
            account: _account,
          );
          _authController.add(authModel);
          return authModel;
        } else {
          final authModel = AuthModel(
            service: SupportedService.filman,
            success: false,
            error: [json['error'] ?? 'Nieznany błąd logowania $webviewLogin'],
          );
          _authController.add(authModel);
          return authModel;
        }
      } catch (e) {
        debugPrint('Błąd parsowania odpowiedzi logowania: $e');

        final authModel = AuthModel(
          service: SupportedService.filman,
          success: false,
          error: ['Błąd parsowania odpowiedzi logowania: $e'],
        );
        _authController.add(authModel);
        return authModel;
      }
    } catch (e) {
      final authModel = AuthModel(
        service: SupportedService.filman,
        success: false,
        error: ['Błąd logowania: $e'],
      );
      _authController.add(authModel);
      return authModel;
    }
  }

  @override
  AccountModel? getAccount() {
    return _account;
  }

  @override
  Future<void> setAccount(AccountModel account) async {
    _account = account;
    _dio = FilmanDioFactory.getDio(_account);

    await SecureStorageService.saveServiceData(
      SupportedService.filman,
      'account',
      jsonEncode(account.toMap()),
    );

    _authController.add(
      AuthModel(
        service: SupportedService.filman,
        success: true,
        account: _account,
      ),
    );
  }

  @override
  Future<void> signOut() async {
    _account = null;
    _dio = FilmanDioFactory.getDio(null);
    _authController.add(
      AuthModel(
        service: SupportedService.filman,
        success: false,
        account: null,
      ),
    );
    await SecureStorageService.deleteServiceData(
      SupportedService.filman,
      'account',
    );
  }

  void dispose() {
    _authSubscription.cancel();
    _authController.close();
  }
}
