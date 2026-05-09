import 'package:purevideo/core/utils/supported_enum.dart';
import 'package:purevideo/data/models/account_model.dart';

class AuthModel {
  final SupportedService service;
  final bool success;
  final AccountModel? account;
  final List<String>? error;

  AuthModel({
    required this.service,
    required this.success,
    this.account,
    this.error,
  });

  @override
  String toString() {
    return 'AuthModel(service: $service, success: $success, account: ${account?.toMap()}, error: $error)';
  }
}
