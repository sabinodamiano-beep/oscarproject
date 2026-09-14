import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../network/api_client.dart';

enum EstadoConexion {
  desconocido,        // todavía no se ha verificado
  online,             // el servidor respondió a GET /api/test
  servidorNoResponde, // hay red pero la API no contesta (o el teléfono cree que hay red)
  sinRed,             // el sistema reporta que no hay conectividad
}

/// Estado global de conexión. Singleton: lo consultan los repositorios para
/// decidir si intentar la API o ir directo al caché, y lo escuchan los
/// widgets de estado (banner offline, indicador).
///
/// Regla: mientras el estado sea `online` o `desconocido` se intenta la API;
/// si es `sinRed` o `servidorNoResponde` se va directo a local, sin esperar
/// el timeout de 30 s. Un fallo de red en cualquier llamada lo baja a
/// `servidorNoResponde` (`marcarCaida`), y una recuperación de red o un ping
/// exitoso lo vuelve a `online`.
class ConnectionMonitor extends ChangeNotifier {
  ConnectionMonitor._();
  static final ConnectionMonitor instance = ConnectionMonitor._();

  static const Duration _pingTimeout = Duration(seconds: 5);
  static const Duration _reintentoCuandoCaido = Duration(seconds: 30);

  EstadoConexion _estado = EstadoConexion.desconocido;
  bool _verificando = false;
  DateTime? _ultimaVerificacion;
  StreamSubscription<List<ConnectivityResult>>? _sub;
  Timer? _timerReintento;

  EstadoConexion get estado => _estado;
  bool get verificando => _verificando;
  DateTime? get ultimaVerificacion => _ultimaVerificacion;

  bool get online => _estado == EstadoConexion.online;
  bool get sinRed => _estado == EstadoConexion.sinRed;

  /// true cuando vale la pena intentar la API.
  bool get intentarRemoto =>
      _estado == EstadoConexion.online || _estado == EstadoConexion.desconocido;

  /// Llamar una vez al arrancar la app (main.dart).
  void iniciar() {
    _sub ??= Connectivity().onConnectivityChanged.listen((results) {
      if (results.isEmpty || results.every((r) => r == ConnectivityResult.none)) {
        _set(EstadoConexion.sinRed);
      } else {
        // Volvió la red: comprobar de verdad contra el servidor.
        verificar();
      }
    });
    verificar();
  }

  /// Ping real: GET /api/test con timeout corto. Devuelve true si online.
  Future<bool> verificar() async {
    if (_verificando) return online;
    _verificando = true;
    notifyListeners();
    final ok = await ApiClient().testConnection(timeout: _pingTimeout);
    _ultimaVerificacion = DateTime.now();
    _verificando = false;
    _set(ok ? EstadoConexion.online : await _estadoSinServidor());
    return ok;
  }

  /// Lo llaman los repositorios cuando una llamada falla por red/timeout.
  void marcarCaida() {
    if (_estado == EstadoConexion.sinRed) return;
    _set(EstadoConexion.servidorNoResponde);
  }

  Future<EstadoConexion> _estadoSinServidor() async {
    try {
      final r = await Connectivity().checkConnectivity();
      if (r.isEmpty || r.every((x) => x == ConnectivityResult.none)) {
        return EstadoConexion.sinRed;
      }
    } catch (_) {}
    return EstadoConexion.servidorNoResponde;
  }

  void _set(EstadoConexion nuevo) {
    final cambio = nuevo != _estado;
    _estado = nuevo;
    _programarReintento();
    if (cambio || !_verificando) notifyListeners();
  }

  /// Mientras estemos caídos, reintentar el ping cada 30 s para volver a
  /// `online` solos, sin que el vendedor tenga que tocar nada.
  void _programarReintento() {
    _timerReintento?.cancel();
    if (_estado == EstadoConexion.online) return;
    _timerReintento = Timer(_reintentoCuandoCaido, verificar);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _timerReintento?.cancel();
    super.dispose();
  }
}
