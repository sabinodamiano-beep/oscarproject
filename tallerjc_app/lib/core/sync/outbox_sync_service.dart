import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../features/pedidos/data/datasources/pedido_remote_datasource.dart';
import '../../features/pedidos/data/models/pedido_local_model.dart';
import '../database/local_database.dart';
import '../errors/exceptions.dart';
import 'connection_monitor.dart';

/// Resultado de encolar un pedido.
class ResultadoEnvio {
  final PedidoLocal pedido;
  /// true si se envió en el acto y ya tiene uid_pedido del servidor.
  bool get enviado => pedido.enviado;
  bool get pendiente => pedido.pendiente;
  bool get fallido => pedido.fallido;
  const ResultadoEnvio(this.pedido);
}

/// Cola de salida de pedidos. Un pedido creado se guarda SIEMPRE primero en
/// SQLite y después se intenta enviar. Envío FIFO, un pedido a la vez, con
/// `client_uuid` para que un reintento nunca duplique (idempotencia en la API).
///
/// Reintentos: al recuperar conexión (ConnectionMonitor → online) y con
/// backoff 5 s → 30 s → 2 min tras fallos de red. Después queda a la espera
/// del próximo cambio de red o de un envío manual.
class OutboxSyncService extends ChangeNotifier {
  OutboxSyncService._() {
    ConnectionMonitor.instance.addListener(_alCambiarConexion);
  }
  static final OutboxSyncService instance = OutboxSyncService._();

  static const List<Duration> _backoff = [
    Duration(seconds: 5),
    Duration(seconds: 30),
    Duration(minutes: 2),
  ];

  final LocalDatabase _local = LocalDatabase.instance;
  final PedidosRemoteDatasource _remote = PedidosRemoteDatasource();

  String? _uidVendedor;
  int _pendientes = 0;
  int _fallidos = 0;
  bool _procesando = false;
  String? _ultimoMensaje;
  Timer? _timerBackoff;
  int _nivelBackoff = 0;
  bool _estabaOnline = false;

  String? get uidVendedor => _uidVendedor;
  int get pendientes => _pendientes;
  int get fallidos => _fallidos;
  int get porAtender => _pendientes + _fallidos;
  bool get procesando => _procesando;
  String? get ultimoMensaje => _ultimoMensaje;
  bool get activo => _uidVendedor != null && _local.abierta;

  // ------------------------------------------------------------ ciclo

  /// Llamar tras el login / sesión restaurada, con la base local ya abierta.
  Future<void> iniciar(String uidVendedor) async {
    _uidVendedor = uidVendedor;
    _estabaOnline = ConnectionMonitor.instance.online;
    try {
      await _local.purgarEnviados();
    } catch (_) {}
    await _refrescarContadores();
    // Si quedó algo de una sesión anterior, intentar de una vez.
    procesar();
  }

  /// Llamar en el logout ANTES de cerrar la base local.
  void detener() {
    _timerBackoff?.cancel();
    _uidVendedor = null;
    _pendientes = 0;
    _fallidos = 0;
    _procesando = false;
    notifyListeners();
  }

  void _alCambiarConexion() {
    final online = ConnectionMonitor.instance.online;
    if (online && !_estabaOnline) {
      _nivelBackoff = 0;
      procesar();
    }
    _estabaOnline = online;
  }

  // ------------------------------------------------------------ cola

  /// Guarda el pedido en el teléfono y lo intenta enviar de inmediato.
  Future<ResultadoEnvio> encolar(PedidoLocal pedido) async {
    await _local.insertarOutbox(pedido.toRow());
    await _refrescarContadores();
    await procesar();
    final fila = await _local.getOutbox(pedido.uuid);
    return ResultadoEnvio(fila == null ? pedido : PedidoLocal.fromRow(fila));
  }

  /// Reemplaza el contenido de un pedido local (edición) y lo vuelve a poner en cola.
  Future<ResultadoEnvio> reemplazar(PedidoLocal pedido) async {
    final limpio = pedido.copyWith(estado: EstadoOutbox.pendiente, intentos: 0, limpiarError: true);
    await _local.insertarOutbox(limpio.toRow());
    await _refrescarContadores();
    await procesar();
    final fila = await _local.getOutbox(pedido.uuid);
    return ResultadoEnvio(fila == null ? limpio : PedidoLocal.fromRow(fila));
  }

  Future<void> descartar(String uuid) async {
    await _local.eliminarOutbox(uuid);
    await _refrescarContadores();
  }

  /// Vuelve a poner en cola un pedido fallido y dispara el envío.
  Future<ResultadoEnvio?> reintentar(String uuid) async {
    final fila = await _local.getOutbox(uuid);
    if (fila == null) return null;
    final p = PedidoLocal.fromRow(fila);
    await _local.actualizarOutbox(uuid, {
      'estado': EstadoOutbox.pendiente,
      'ultimo_error': null,
      'fecmod': DateTime.now().toIso8601String(),
    });
    await _refrescarContadores();
    await procesar();
    final f2 = await _local.getOutbox(uuid);
    return ResultadoEnvio(f2 == null ? p : PedidoLocal.fromRow(f2));
  }

  Future<List<PedidoLocal>> listarVisibles() async {
    if (!activo) return const [];
    final filas = await _local.listarOutbox(_uidVendedor!,
        estados: [EstadoOutbox.pendiente, EstadoOutbox.fallido]);
    return filas.map(PedidoLocal.fromRow).toList();
  }

  Future<PedidoLocal?> get(String uuid) async {
    if (!activo) return null;
    final fila = await _local.getOutbox(uuid);
    return fila == null ? null : PedidoLocal.fromRow(fila);
  }

  // ------------------------------------------------------------ envío

  /// Envía los pendientes en orden FIFO. Se detiene al primer fallo de red.
  /// Nunca lanza: los errores quedan en cada pedido o en [ultimoMensaje].
  Future<void> procesar() async {
    if (_procesando || !activo) return;
    if (!ConnectionMonitor.instance.intentarRemoto) {
      _ultimoMensaje = 'Sin conexión: los pedidos se enviarán al recuperar señal';
      notifyListeners();
      return;
    }

    _procesando = true;
    _timerBackoff?.cancel();
    notifyListeners();

    var enviados = 0;
    var falloRed = false;

    try {
      final filas = await _local.listarOutbox(_uidVendedor!,
          estados: [EstadoOutbox.pendiente], fifo: true);

      for (final fila in filas) {
        if (!activo) break; // logout a mitad de camino
        final p = PedidoLocal.fromRow(fila);
        try {
          final resp = await _remote.crearPedido(p.toCreateJson());
          final uid = resp['uid_pedido']?.toString();
          await _local.actualizarOutbox(p.uuid, {
            'estado': EstadoOutbox.enviado,
            'uid_pedido': uid,
            'intentos': p.intentos + 1,
            'ultimo_error': null,
            'fecmod': DateTime.now().toIso8601String(),
          });
          enviados++;
        } on NetworkException catch (e) {
          await _marcarIntento(p, e.message);
          ConnectionMonitor.instance.marcarCaida();
          falloRed = true;
          break;
        } on AppTimeoutException catch (e) {
          await _marcarIntento(p, e.message);
          ConnectionMonitor.instance.marcarCaida();
          falloRed = true;
          break;
        } on UnauthorizedException {
          // ApiClient ya disparó el logout; la cola espera al próximo login.
          break;
        } on ServerException catch (e) {
          // 400/404: el servidor rechazó ESTE pedido. Los demás siguen.
          await _local.actualizarOutbox(p.uuid, {
            'estado': EstadoOutbox.fallido,
            'intentos': p.intentos + 1,
            'ultimo_error': e.message,
            'fecmod': DateTime.now().toIso8601String(),
          });
        } catch (e) {
          await _marcarIntento(p, 'Error inesperado: $e');
          break;
        }
      }
    } catch (_) {
      // base cerrada por logout u otro fallo: salir en silencio
    }

    if (activo) {
      await _refrescarContadores();
      if (enviados > 0) {
        _ultimoMensaje = enviados == 1 ? '1 pedido enviado' : '$enviados pedidos enviados';
        _nivelBackoff = 0;
      }
      if (falloRed && _pendientes > 0) {
        _programarBackoff();
      }
    }
    _procesando = false;
    notifyListeners();
  }

  Future<void> _marcarIntento(PedidoLocal p, String error) async {
    await _local.actualizarOutbox(p.uuid, {
      'intentos': p.intentos + 1,
      'ultimo_error': error,
      'fecmod': DateTime.now().toIso8601String(),
    });
  }

  void _programarBackoff() {
    _timerBackoff?.cancel();
    if (_nivelBackoff >= _backoff.length) {
      _ultimoMensaje = 'Se reintentará al recuperar conexión';
      return;
    }
    final espera = _backoff[_nivelBackoff++];
    _ultimoMensaje = 'Reintentando en ${espera.inSeconds < 60 ? '${espera.inSeconds} s' : '${espera.inMinutes} min'}';
    _timerBackoff = Timer(espera, procesar);
  }

  Future<void> _refrescarContadores() async {
    if (!activo) return;
    try {
      _pendientes = await _local.contarOutbox(_uidVendedor!, [EstadoOutbox.pendiente]);
      _fallidos = await _local.contarOutbox(_uidVendedor!, [EstadoOutbox.fallido]);
    } catch (_) {}
    notifyListeners();
  }

  @override
  void dispose() {
    ConnectionMonitor.instance.removeListener(_alCambiarConexion);
    _timerBackoff?.cancel();
    super.dispose();
  }
}
