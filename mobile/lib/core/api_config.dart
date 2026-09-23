/// Compile-time API endpoint selection for development and release builds.
abstract final class ApiConfig {
  static const development = 'development';
  static const test = 'test';
  static const production = 'production';

  static const environment = String.fromEnvironment(
    'API_ENV',
    defaultValue: bool.fromEnvironment('dart.vm.product')
        ? production
        : development,
  );

  static const developmentBaseUrl = 'http://127.0.0.1:8000';
  static const testBaseUrl = 'http://8.134.70.237';
  static const productionBaseUrl = 'http://8.134.70.237';

  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: environment == test
        ? testBaseUrl
        : environment == production
        ? productionBaseUrl
        : developmentBaseUrl,
  );

  static void validate() {
    if (const bool.fromEnvironment('dart.vm.product') &&
        environment != production) {
      throw StateError('Release builds require API_ENV=production.');
    }
    if (environment == production) validateProductionOrigin(baseUrl);
  }

  static void validateProductionOrigin(String origin) {
    final url = Uri.tryParse(origin);
    if (url == null ||
        (url.scheme != 'https' && origin != productionBaseUrl) ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty ||
        (url.path.isNotEmpty && url.path != '/') ||
        url.hasQuery ||
        url.hasFragment) {
      throw StateError(
        'Production API_BASE_URL must be an HTTPS origin or the approved v1.0 ECS HTTP origin.',
      );
    }
  }
}
