import 'dart:convert';

/// Estados de un cobro en la cola local.
class EstadoCobroOutbox {
  static const String pendiente = 'pendiente'; // esperando red / reintento
  static const String enviado = 'enviado';     // ya tiene numpago del servidor
  /// El servidor lo rechazó al sincronizar (p. ej. la deuda cambió y el abono
  /// supera el disponible). OJO: el vendedor ya recibió el dinero; requiere
  /// resolverse a mano (reintentar tras revisar, o descartar y avisar a la
  /// oficina). Nunca se purga solo.
  static const String rechazado = 'rechazado';
}

/// Cobro guardado en el teléfono (tabla `cobros_outbox`).
///
/// [payload] es el body EXACTO de POST /cobros (incluye client_uuid = uuid,
/// así un reintento tras un corte nunca duplica: la API hace replay).
/// [resumen] guarda lo necesario para pintar la tarjeta del historial y el
/// recibo PDF sin conexión, con las MISMAS llaves que devuelve la API en el
/// detalle (Abreviatura/iddoc/monto en documentos; forma_pago/monto/cambio/
/// montobs/banco/referencia en formas).
class CobroLocal {
  final String uuid;
  final String uidVendedor;
  final int uidCliente;
  final String clienteNombre;
  final Map<String, dynamic> payload;
  final Map<String, dynamic> resumen;
  final double total;
  final String estado;
  final int intentos;
  final String? ultimoError;
  final String? numpago;
  final DateTime fecreg;
  final DateTime fecmod;

  const CobroLocal({
    required this.uuid,
    required this.uidVendedor,
    required this.uidCliente,
    required this.clienteNombre,
    required this.payload,
    required this.resumen,
    required this.total,
    this.estado = EstadoCobroOutbox.pendiente,
    this.intentos = 0,
    this.ultimoError,
    this.numpago,
    required this.fecreg,
    required this.fecmod,
  });

  bool get pendiente => estado == EstadoCobroOutbox.pendiente;
  bool get enviado => estado == EstadoCobroOutbox.enviado;
  bool get rechazado => estado == EstadoCobroOutbox.rechazado;

  List<Map<String, dynamic>> get documentosResumen =>
      ((resumen['documentos'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

  List<Map<String, dynamic>> get formasResumen =>
      ((resumen['formas'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

  // ------------------------------------------------------------ SQLite

  Map<String, Object?> toRow() => {
        'uuid': uuid,
        'uid_vendedor': uidVendedor,
        'uid_cliente': uidCliente,
        'cliente_nombre': clienteNombre,
        'payload_json': jsonEncode(payload),
        'resumen_json': jsonEncode(resumen),
        'total': total,
        'estado': estado,
        'intentos': intentos,
        'ultimo_error': ultimoError,
        'numpago': numpago,
        'fecreg': fecreg.toIso8601String(),
        'fecmod': fecmod.toIso8601String(),
      };

  factory CobroLocal.fromRow(Map<String, Object?> r) => CobroLocal(
        uuid: r['uuid'] as String,
        uidVendedor: r['uid_vendedor'] as String,
        uidCliente: (r['uid_cliente'] as num).toInt(),
        clienteNombre: (r['cliente_nombre'] ?? '') as String,
        payload: Map<String, dynamic>.from(
            jsonDecode(r['payload_json'] as String) as Map),
        resumen: Map<String, dynamic>.from(
            jsonDecode(r['resumen_json'] as String) as Map),
        total: (r['total'] as num?)?.toDouble() ?? 0,
        estado: (r['estado'] ?? EstadoCobroOutbox.pendiente) as String,
        intentos: (r['intentos'] as num?)?.toInt() ?? 0,
        ultimoError: r['ultimo_error'] as String?,
        numpago: r['numpago'] as String?,
        fecreg: DateTime.tryParse((r['fecreg'] ?? '') as String) ?? DateTime.now(),
        fecmod: DateTime.tryParse((r['fecmod'] ?? '') as String) ?? DateTime.now(),
      );

  CobroLocal copyWith({
    String? estado,
    int? intentos,
    String? ultimoError,
    bool limpiarError = false,
    String? numpago,
    DateTime? fecmod,
  }) =>
      CobroLocal(
        uuid: uuid,
        uidVendedor: uidVendedor,
        uidCliente: uidCliente,
        clienteNombre: clienteNombre,
        payload: payload,
        resumen: resumen,
        total: total,
        estado: estado ?? this.estado,
        intentos: intentos ?? this.intentos,
        ultimoError: limpiarError ? null : (ultimoError ?? this.ultimoError),
        numpago: numpago ?? this.numpago,
        fecreg: fecreg,
        fecmod: fecmod ?? DateTime.now(),
      );
}
