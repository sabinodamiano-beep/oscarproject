import 'dart:convert';

import '../../../clientes/domain/entities/cliente.dart';
import '../../../items/domain/entities/item.dart';

/// Estados de un pedido en la cola local.
class EstadoOutbox {
  static const String pendiente = 'pendiente'; // esperando red / reintento
  static const String enviado = 'enviado';     // ya tiene uid_pedido del servidor
  static const String fallido = 'fallido';     // el servidor lo rechazó (400/404): requiere acción del vendedor
}

/// Línea de un pedido local. Guarda lo necesario para (a) enviar a la API y
/// (b) volver a cargar el carrito para editarlo sin conexión.
class LineaLocal {
  final String coditems;
  final String descripcion;
  final double cajas;
  final double botellas;
  /// Precio unitario efectivo con el que se armó la línea (ya con el nivel
  /// aplicado). Se guarda para poder mostrar totales estando sin señal.
  final double dolPre;
  /// Nivel de precio elegido por el vendedor (pvp, ofe, may, dis, esp).
  final String precioNivel;
  final double cantunidad;
  final bool ventaBotella;
  final String nombreLinea;
  final String nombrePresentacion;

  const LineaLocal({
    required this.coditems,
    required this.descripcion,
    required this.cajas,
    required this.botellas,
    required this.dolPre,
    this.precioNivel = 'pvp',
    required this.cantunidad,
    required this.ventaBotella,
    this.nombreLinea = '',
    this.nombrePresentacion = '',
  });

  double get total {
    final fraccion = cantunidad > 0 ? botellas / cantunidad : 0;
    return _round2((cajas + fraccion) * dolPre);
  }

  Map<String, dynamic> toJson() => {
        'coditems': coditems,
        'descripcion': descripcion,
        'cajas': cajas,
        'botellas': botellas,
        'dolPre': dolPre,
        'precioNivel': precioNivel,
        'cantunidad': cantunidad,
        'ventaBotella': ventaBotella,
        'nombreLinea': nombreLinea,
        'nombrePresentacion': nombrePresentacion,
      };

  factory LineaLocal.fromJson(Map<String, dynamic> j) => LineaLocal(
        coditems: (j['coditems'] ?? '').toString(),
        descripcion: (j['descripcion'] ?? '').toString(),
        cajas: _d(j['cajas']),
        botellas: _d(j['botellas']),
        dolPre: _d(j['dolPre']),
        precioNivel: (j['precioNivel'] ?? 'pvp').toString(),
        cantunidad: j['cantunidad'] == null ? 1 : _d(j['cantunidad']),
        ventaBotella: j['ventaBotella'] == true,
        nombreLinea: (j['nombreLinea'] ?? '').toString(),
        nombrePresentacion: (j['nombrePresentacion'] ?? '').toString(),
      );

  /// Lo que espera POST /pedidos
  Map<String, dynamic> toApiJson() =>
      {'coditems': coditems, 'cajas': cajas, 'botellas': botellas, 'precio_nivel': precioNivel};

  /// Reconstruye un Item mínimo para volver a cargar el carrito
  Item toItem() => Item(
        coditems: coditems,
        desitems: descripcion,
        existencia: 0,
        ubicacion: '',
        codBarra: '',
        activo: '1',
        status: '',
        precioPvp: 0,
        precioEspecial: 0,
        precioDistribuidor: 0,
        precioMayor: 0,
        precioOferta: 0,
        ventaCaja: '1',
        ventaBotella: ventaBotella ? '1' : '0',
        litros: 0,
        codMarca: 0,
        codLinea: 0,
        codPresentacion: 0,
        nombreMarca: '',
        dolPre: precioNivel == 'pvp' ? dolPre : 0,
        dolOfe: precioNivel == 'ofe' ? dolPre : 0,
        dolMay: precioNivel == 'may' ? dolPre : 0,
        dolDis: precioNivel == 'dis' ? dolPre : 0,
        dolEsp: precioNivel == 'esp' ? dolPre : 0,
        cantunidad: cantunidad,
        nombreLinea: nombreLinea,
        nombrePresentacion: nombrePresentacion,
      );
}

/// Pedido guardado en el teléfono (tabla `pedidos_outbox`).
class PedidoLocal {
  final String uuid;
  final String uidVendedor;
  final int uidCliente;
  final String clienteNombre;
  final String observaciones;
  final List<LineaLocal> lineas;
  final String estado;
  final int intentos;
  final String? ultimoError;
  final String? uidPedido;
  final DateTime fecreg;
  final DateTime fecmod;

  const PedidoLocal({
    required this.uuid,
    required this.uidVendedor,
    required this.uidCliente,
    required this.clienteNombre,
    required this.observaciones,
    required this.lineas,
    this.estado = EstadoOutbox.pendiente,
    this.intentos = 0,
    this.ultimoError,
    this.uidPedido,
    required this.fecreg,
    required this.fecmod,
  });

  double get total => _round2(lineas.fold(0.0, (s, l) => s + l.total));
  int get totalItems => lineas.length;
  bool get pendiente => estado == EstadoOutbox.pendiente;
  bool get fallido => estado == EstadoOutbox.fallido;
  bool get enviado => estado == EstadoOutbox.enviado;
  bool get tieneObservaciones => observaciones.trim().isNotEmpty;

  /// Body para POST /pedidos, con la llave de idempotencia.
  Map<String, dynamic> toCreateJson() => {
        'uid_cliente': uidCliente,
        if (observaciones.trim().isNotEmpty) 'observaciones': observaciones.trim(),
        'items': lineas.map((l) => l.toApiJson()).toList(),
        'client_uuid': uuid,
      };

  /// Cliente mínimo para el carrito.
  Cliente toCliente() => Cliente(
        uidCliente: uidCliente,
        codigo: '',
        cedula: '',
        tipoCedula: '',
        nombres: clienteNombre,
        apellidos: '',
        telefonoCelular: '',
        telefonoCasa: '',
        telefonoOficina: '',
        direccion: '',
        email: '',
        comentario: '',
        status: '',
      );

  // ------------------------------------------------------------ SQLite

  Map<String, Object?> toRow() => {
        'uuid': uuid,
        'uid_vendedor': uidVendedor,
        'uid_cliente': uidCliente,
        'cliente_nombre': clienteNombre,
        'observaciones': observaciones,
        'items_json': jsonEncode(lineas.map((l) => l.toJson()).toList()),
        'total_local': total,
        'total_items': totalItems,
        'estado': estado,
        'intentos': intentos,
        'ultimo_error': ultimoError,
        'uid_pedido': uidPedido,
        'fecreg': fecreg.toIso8601String(),
        'fecmod': fecmod.toIso8601String(),
      };

  factory PedidoLocal.fromRow(Map<String, Object?> r) {
    final lista = jsonDecode(r['items_json'] as String) as List;
    return PedidoLocal(
      uuid: r['uuid'] as String,
      uidVendedor: r['uid_vendedor'] as String,
      uidCliente: (r['uid_cliente'] as num).toInt(),
      clienteNombre: (r['cliente_nombre'] ?? '') as String,
      observaciones: (r['observaciones'] ?? '') as String,
      lineas: lista.map((e) => LineaLocal.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      estado: (r['estado'] ?? EstadoOutbox.pendiente) as String,
      intentos: (r['intentos'] as num?)?.toInt() ?? 0,
      ultimoError: r['ultimo_error'] as String?,
      uidPedido: r['uid_pedido'] as String?,
      fecreg: DateTime.tryParse((r['fecreg'] ?? '') as String) ?? DateTime.now(),
      fecmod: DateTime.tryParse((r['fecmod'] ?? '') as String) ?? DateTime.now(),
    );
  }

  PedidoLocal copyWith({
    String? clienteNombre,
    int? uidCliente,
    String? observaciones,
    List<LineaLocal>? lineas,
    String? estado,
    int? intentos,
    String? ultimoError,
    bool limpiarError = false,
    String? uidPedido,
    DateTime? fecmod,
  }) =>
      PedidoLocal(
        uuid: uuid,
        uidVendedor: uidVendedor,
        uidCliente: uidCliente ?? this.uidCliente,
        clienteNombre: clienteNombre ?? this.clienteNombre,
        observaciones: observaciones ?? this.observaciones,
        lineas: lineas ?? this.lineas,
        estado: estado ?? this.estado,
        intentos: intentos ?? this.intentos,
        ultimoError: limpiarError ? null : (ultimoError ?? this.ultimoError),
        uidPedido: uidPedido ?? this.uidPedido,
        fecreg: fecreg,
        fecmod: fecmod ?? DateTime.now(),
      );
}

double _round2(double n) => (n * 100).roundToDouble() / 100;

double _d(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString().trim()) ?? 0;
}
