import 'package:flutter_test/flutter_test.dart';
import 'package:grand_prix_reminder/core/api_config.dart';

void main() {
  test('selects the configured backend environment', () {
    expect(ApiConfig.baseUrl, switch (ApiConfig.environment) {
      ApiConfig.test => ApiConfig.testBaseUrl,
      ApiConfig.production => const String.fromEnvironment('API_BASE_URL'),
      _ => ApiConfig.developmentBaseUrl,
    });
    if (ApiConfig.environment == ApiConfig.production &&
        ApiConfig.baseUrl.isEmpty) {
      expect(() => ApiConfig.validate(), throwsStateError);
    } else {
      expect(ApiConfig.validate, returnsNormally);
    }
  });
}
