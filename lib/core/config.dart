/// Build-time configuration.
///
/// Defaults point at the production API used by the web app. Override for
/// local development with:
///   flutter run --dart-define=API_URL=http://10.0.2.2:8000
class AppConfig {
  AppConfig._();

  static const String apiBase = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://taskforge-api-mu6x.onrender.com',
  );

  static const String wsBase = String.fromEnvironment(
    'WS_URL',
    defaultValue: 'wss://taskforge-api-mu6x.onrender.com',
  );

  static const String webUrl = 'https://taskforge-app-869.netlify.app';
  static const String docsUrl =
      'https://abdullah-masood-05.github.io/taskforge-site/';

  static String get apiPrefix => '$apiBase/api/v1';
}
