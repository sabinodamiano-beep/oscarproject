import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../features/cobros/data/datasources/cobro_remote_datasource.dart';
import '../../features/cobros/data/models/cobro_local_model.dart';
import '../database/local_database.dart';
import '../errors/exceptions.dart';
import 'connection_monitor.dart';

/// Resultado de encolar un cobro.
class ResultadoCobro {
  final CobroLocal cobro;
  bool get enviado => cobro.enviado;
  bool get pendiente => cobro.pendiente;
  const ResultadoCobro(this.cobro);
}

/// Cola de salida de COBROS. Mismo patrón que la de pedidos, con una
/// diferencia deliberada en el manejo de rechazos del servidor:
///
/// - Al CREAR (vendedor en pantalla): si el servidor rechaza el cobro
///   (400/409), la fila se ELIMINA y el error sube a la pantalla para que
///   el vendedor lo corrija en el momento.
/// - Al SINCRONIZAR uno encolado sin señal: un rechazo (p. ej. la deuda
///   cambió y el abono supera el disponible) marca el cobro como RECHAZADO
///   con el mensaje del servidor. El vendedor YA recibió el dinero, así que
///   la app nunca lo descarta sola: queda visible en rojo hasta que él lo
///   reintente (tras revisar) o lo descarte y lo resuelva con la oficina.
///
/// La idempotencia por client_uuid (= uuid de la fila) vive en la API:
/// un reintento tras un corte de red hace replay y nunca duplica.
class CobrosOutboxService extends ChangeNotifier {
  CobrosOutboxService._() {
    ConnectionMonitor.instance.addListener(_alCambiarConexion);
  }
  static final CobrosOutboxService instance = CobrosOutboxService._();

  static const List<Duration> _backoff = [
    Duration(seconds: 5),
    Duration(seconds: 30),
    Duration(minutes: 2),
  ];

  final LocalDatabase _local = LocalDatabase.instance;
  final CobrosRemoteDatasource _remote = CobrosRemoteDatasource();

  String? _uidVendedor;
  int _pendientes = 0;
  int _rechazados = 0;
  bool _procesando = false;
  String? _ultimoMensaje;
  Timer? _timerBackoff;
  int _nivelBackoff = 0;
  bool _estabaOnline = false;

  String? get uidVendedor => _uidVendedor;
  int get pendientes => _pendientes;
  int get rechazados => _rechazados;
  int get porAtender => _pendientes + _rechazados;
  bool get procesando => _procesando;
  String? get ultimoMensaje => _ultimoMensaje;
  bool get activo => _uidVendedor != null && _local.abierta;

  // ------------------------------------------------------------ ciclo

  /// Llamar tras el login / sesión restaurada, con la base local ya abierta.
  Future<void> iniciar(String uidVendedor) async {
    _uidVendedor = uidVendedor;
    _estabaOnline = ConnectionMonitor.instance.online;
    try {
      await _local.purgarCobrosEnviados();
    } catch (_) {}
    await _refrescarContadores();
    procesar();
  }

  /// Llamar en el logout ANTES de cerrar la base local.
  void detener() {
    _timerBackoff?.cancel();
    _uidVendedor = null;
    _pendientes = 0;
    _rechazados = 0;
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

  /// Guarda el cobro en el teléfono y lo intenta enviar de inmediato.
  ///
  /// - Enviado: devuelve el cobro con su numpago.
  /// - Sin red / timeout: queda PENDIENTE y devuelve así.
  /// - Rechazo del servidor (400/409): ELIMINA la fila y relanza la
  ///   excepción para que la pantalla la muestre y el vendedor corrija.
  Future<ResultadoCobro> encolar(CobroLocal cobro) async {
    await _local.insertarCobroOutbox(cobro.toRow());
    await _refrescarContadores();

    if (!ConnectionMonitor.instance.intentarRemoto) {
      _ultimoMensaje = 'Sin conexión: el cobro se enviará al recuperar señal';
      notifyListeners();
      return ResultadoCobro(cobro);
    }

    try {
      final resp = await _remote.crearCobro(cobro.payload);
      final enviado = cobro.copyWith(
        estado: EstadoCobroOutbox.enviado,
        numpago: '${resp['numpago'] ?? ''}',
        intentos: cobro.intentos + 1,
        limpiarError: true,
      );
      await _local.actualizarCobroOutbox(cobro.uuid, enviado.toRow());
      await _refrescarContadores();
      return ResultadoCobro(enviado);
    } on NetworkException {
      ConnectionMonitor.instance.marcarCaida();
      await _marcarIntento(cobro, 'Sin conexión');
      _programarBackoff();
      notifyListeners();
      return ResultadoCobro(cobro.copyWith(intentos: cobro.intentos + 1));
    } on AppTimeoutException {
      ConnectionMonitor.instance.marcarCaida();
      await _marcarIntento(cobro, 'El servidor no respondió');
      _programarBackoff();
      notifyListeners();
      return ResultadoCobro(cobro.copyWith(intentos: cobro.intentos + 1));
    } on ServerException {
      // Rechazo con el vendedor en pantalla: fuera de la cola, que corrija ya.
      await _local.eliminarCobroOutbox(cobro.uuid);
      await _refrescarContadores();
      rethrow;
    }
  }

  /// Vuelve a poner en cola un cobro rechazado y dispara el envío.
  Future<void> reintentar(String uuid) async {
    await _local.actualizarCobroOutbox(uuid, {
      'estado': EstadoCobroOutbox.pendiente,
      'ultimo_error': null,
      'fecmod': DateTime.now().toIso8601String(),
    });
    await _refrescarContadores();
    await procesar();
  }

  /// Descarta un cobro local (el vendedor asume resolverlo con la oficina).
  Future<void> descartar(String uuid) async {
    await _local.eliminarCobroOutbox(uuid);
    await _refrescarContadores();
  }

  Future<CobroLocal?> get(String uuid) async {
    if (!activo) return null;
    final fila = await _local.getCobroOutbox(uuid);
    return fila == null ? null : CobroLocal.fromRow(fila);
  }

  /// Cobros locales que el vendedor debe ver: pendientes y rechazados.
  Future<List<CobroLocal>> listarVisibles() async {
    if (!activo) return const [];
    final filas = await _local.listarCobrosOutbox(_uidVendedor!,
        estados: [EstadoCobroOutbox.pendiente, EstadoCobroOutbox.rechazado]);
    return filas.map(CobroLocal.fromRow).toList();
  }

  // ------------------------------------------------------------ envío

  /// Envía los pendientes en orden FIFO. Se detiene al primer fallo de red.
  /// Nunca lanza: los errores quedan en cada cobro o en [ultimoMensaje].
  Future<void> procesar() async {
    if (_procesando || !activo) return;
    if (!ConnectionMonitor.instance.intentarRemoto) {
      _ultimoMensaje = 'Sin conexión: los cobros se enviarán al recuperar señal';
      notifyListeners();
      return;
    }

    _procesando = true;
    _timerBackoff?.cancel();
    notifyListeners();

    var enviados = 0;
    var falloRed = false;

    try {
      final filas = await _local.listarCobrosOutbox(_uidVendedor!,
          estados: [EstadoCobroOutbox.pendiente], fifo: true);

      for (final fila in filas) {
        if (!activo) break; // logout a mitad de camino
        final c = CobroLocal.fromRow(fila);
        try {
          final resp = await _remote.crearCobro(c.payload);
          await _local.actualizarCobroOutbox(c.uuid, {
            'estado': EstadoCobroOutbox.enviado,
            'numpago': '${resp['numpago'] ?? ''}',
            'intentos': c.intentos + 1,
            'ultimo_error': null,
            'fecmod': DateTime.now().toIso8601String(),
          });
          enviados++;
        } on NetworkException catch (e) {
          await _marcarIntento(c, e.message);
          ConnectionMonitor.instance.marcarCaida();
          falloRed = true;
          break;
        } on AppTimeoutException catch (e) {
          await _marcarIntento(c, e.message);
          ConnectionMonitor.instance.marcarCaida();
          falloRed = true;
          break;
        } on UnauthorizedException {
          break; // ApiClient ya disparó el logout
        } on ServerException catch (e) {
          // El servidor rechazó ESTE cobro (la deuda pudo cambiar).
          // Queda RECHAZADO a la vista del vendedor; los demás siguen.
          await _local.actualizarCobroOutbox(c.uuid, {
            'estado': EstadoCobroOutbox.rechazado,
            'intentos': c.intentos + 1,
            'ultimo_error': e.message,
            'fecmod': DateTime.now().toIso8601String(),
          });
        } catch (e) {
          await _marcarIntento(c, 'Error inesperado: $e');
          break;
        }
      }
    } catch (_) {
      // base cerrada por logout u otro fallo: salir en silencio
    }

    if (activo) {
      await _refrescarContadores();
      if (enviados > 0) {
        _ultimoMensaje = enviados == 1 ? '1 cobro enviado' : '$enviados cobros enviados';
        _nivelBackoff = 0;
      }
      if (falloRed && _pendientes > 0) {
        _programarBackoff();
      }
    }
    _procesando = false;
    notifyListeners();
  }

  Future<void> _marcarIntento(CobroLocal c, String error) async {
    await _local.actualizarCobroOutbox(c.uuid, {
      'intentos': c.intentos + 1,
      'ultimo_error': error,
      'fecmod': DateTime.now().toIso8601String(),
    });
    await _refrescarContadores();
  }

  void _programarBackoff() {
    _timerBackoff?.cancel();
    if (_nivelBackoff >= _backoff.length) {
      _ultimoMensaje = 'Se reintentará al recuperar conexión';
      return;
    }
    final espera = _backoff[_nivelBackoff++];
    _ultimoMensaje =
        'Reintentando en ${espera.inSeconds < 60 ? '${espera.inSeconds} s' : '${espera.inMinutes} min'}';
    _timerBackoff = Timer(espera, procesar);
  }

  Future<void> _refrescarContadores() async {
    if (!activo) return;
    try {
      _pendientes =
          await _local.contarCobrosOutbox(_uidVendedor!, [EstadoCobroOutbox.pendiente]);
      _rechazados =
          await _local.contarCobrosOutbox(_uidVendedor!, [EstadoCobroOutbox.rechazado]);
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
