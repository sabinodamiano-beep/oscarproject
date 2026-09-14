import 'dart:async' show TimeoutException;
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../constants/api_constants.dart';
import '../errors/exceptions.dart';

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;
  ApiClient._internal();

  String? _token;

  /// Callback que se ejecuta cuando el token JWT expira (401)
  /// Se configura desde main.dart para hacer logout automático
  Function()? onSessionExpired;

  void setToken(String token) {
    _token = token;
  }

  void clearToken() {
    _token = null;
  }

  String? get token => _token;

  Map<String, String> get _headers {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
    }
    return headers;
  }

  /// GET request. [timeout] opcional para llamadas que deben fallar rápido
  /// (ping de conexión, lecturas con fallback a caché local).
  Future<dynamic> get(String endpoint, {Duration? timeout}) async {
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}$endpoint');
      final response = await http
          .get(url, headers: _headers)
          .timeout(timeout ?? ApiConstants.timeout);

      return _handleResponse(response);
    } on SocketException {
      throw NetworkException();
    } on TimeoutException {
      throw AppTimeoutException();
    }
  }

  /// POST request
  Future<dynamic> post(String endpoint, Map<String, dynamic> body) async {
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}$endpoint');
      final response = await http
          .post(url, headers: _headers, body: jsonEncode(body))
          .timeout(ApiConstants.timeout);

      return _handleResponse(response);
    } on SocketException {
      throw NetworkException();
    } on TimeoutException {
      throw AppTimeoutException();
    }
  }

  /// PUT request
  Future<dynamic> put(String endpoint, Map<String, dynamic> body) async {
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}$endpoint');
      final response = await http
          .put(url, headers: _headers, body: jsonEncode(body))
          .timeout(ApiConstants.timeout);

      return _handleResponse(response);
    } on SocketException {
      throw NetworkException();
    } on TimeoutException {
      throw AppTimeoutException();
    }
  }

  /// DELETE request (body opcional)
  Future<dynamic> delete(String endpoint, {Map<String, dynamic>? body}) async {
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}$endpoint');
      final response = await http
          .delete(url, headers: _headers, body: body != null ? jsonEncode(body) : null)
          .timeout(ApiConstants.timeout);

      return _handleResponse(response);
    } on SocketException {
      throw NetworkException();
    } on TimeoutException {
      throw AppTimeoutException();
    }
  }

  /// Manejar respuesta del servidor
  dynamic _handleResponse(http.Response response) {
    final body = jsonDecode(response.body);

    switch (response.statusCode) {
      case 200:
      case 201:
        return body;
      case 400:
        throw ServerException(
          message: body['error'] ?? 'Datos incorrectos',
          statusCode: 400,
        );
      case 401:
        // Sesión expirada → ejecutar callback de logout global
        onSessionExpired?.call();
        throw UnauthorizedException(
          message: body['error'] ?? 'Sesión expirada',
        );
      case 403:
      case 404:
      case 409:
        throw ServerException(
          message: body['error'] ?? 'No encontrado',
          statusCode: response.statusCode,
        );
      case 500:
        // Si el servidor explica qué pasó, mostrarlo: ayuda a diagnosticar
        // sin tener que ir a los logs de la PC.
        throw ServerException(
          message: body['error'] ?? 'Error interno del servidor',
          statusCode: 500,
        );
      default:
        throw ServerException(
          message: 'Error inesperado (${response.statusCode})',
          statusCode: response.statusCode,
        );
    }
  }

  /// Verificar conexión con el servidor (timeout corto por defecto: un ping
  /// no debe hacer esperar 30 s a nadie).
  Future<bool> testConnection({Duration timeout = const Duration(seconds: 5)}) async {
    try {
      await get(ApiConstants.test, timeout: timeout);
      return true;
    } catch (_) {
      return false;
    }
  }
}