import 'package:flutter_test/flutter_test.dart';
import 'package:grand_prix_reminder/core/api_config.dart';

void main() {
  test('selects the configured backend environment', () {
    expect(ApiConfig.baseUrl, switch (ApiConfig.environment) {
      ApiConfig.test => ApiConfig.testBaseUrl,
      ApiConfig.production => const String.fromEnvironment(
        'API_BASE_URL',
        defaultValue: ApiConfig.productionBaseUrl,
      ),
      _ => ApiConfig.developmentBaseUrl,
    });
    expect(ApiConfig.validate, returnsNormally);
  });

  test('production permits only the v1.0 HTTP origin or an HTTPS origin', () {
    expect(
      () => ApiConfig.validateProductionOrigin(ApiConfig.productionBaseUrl),
      returnsNormally,
    );
    expect(
      () => ApiConfig.validateProductionOrigin('https://api.example.com'),
      returnsNormally,
    );
    for (final url in [
      'http://other.example.com',
      'http://8.134.70.237:8000',
      'http://8.134.70.237/api',
      'https://api.example.com/api',
    ]) {
      expect(() => ApiConfig.validateProductionOrigin(url), throwsStateError);
    }
  });
}
