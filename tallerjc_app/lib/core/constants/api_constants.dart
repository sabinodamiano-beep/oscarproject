class ApiConstants {
  // En desarrollo local apunta a tu PC
  static const String baseUrl = 'https://desktop-mjilhov.tail048866.ts.net/api';

  // Para dispositivo físico en la misma red WiFi, usar IP local de tu PC:
  // static const String baseUrl = 'http://192.168.X.X:3000/api';

  // Para producción (servidor de Sabino):
  // static const String baseUrl = 'http://IP_PUBLICA_SABINO:3000/api';

  static const Duration timeout = Duration(seconds: 30);
  static const String appVersion = '1.2.0';
  static const String appName = 'GyfSoftware Movil';

  // Endpoints
  static const String login = '/login';
  static const String empresas = '/empresas';
  static const String test = '/test';
  static const String dashboard = '/dashboard';
  static const String clientes = '/clientes';
  static const String productos = '/productos';
  static const String marcas = '/marcas';
  static const String lineas = '/lineas';
  static const String presentaciones = '/presentaciones';
  static const String pedidos = '/pedidos';
}
