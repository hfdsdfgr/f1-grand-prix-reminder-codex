/// Compile-time API endpoint selection for local development and device tests.
abstract final class ApiConfig {
  static const development = 'development';
  static const test = 'test';

  static const environment = String.fromEnvironment(
    'API_ENV',
    defaultValue: development,
  );

  static const developmentBaseUrl = 'http://127.0.0.1:8000';
  static const testBaseUrl = 'http://8.134.70.237';

  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: environment == test ? testBaseUrl : developmentBaseUrl,
  );
}
