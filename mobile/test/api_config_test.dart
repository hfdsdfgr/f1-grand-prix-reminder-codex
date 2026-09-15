import 'package:flutter_test/flutter_test.dart';
import 'package:grand_prix_reminder/core/api_config.dart';

void main() {
  test('selects the configured backend environment', () {
    final isTest = ApiConfig.environment == ApiConfig.test;
    expect(
      ApiConfig.baseUrl,
      isTest ? ApiConfig.testBaseUrl : ApiConfig.developmentBaseUrl,
    );
  });
}
