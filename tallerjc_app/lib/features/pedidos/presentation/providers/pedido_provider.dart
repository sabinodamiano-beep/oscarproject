import 'dart:math';

import 'package:flutter/material.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/sync/connection_monitor.dart';
import '../../../../core/sync/outbox_sync_service.dart';
import '../../data/models/pedido_local_model.dart';
import '../../../clientes/domain/entities/cliente.dart';
import '../../../items/domain/entities/item.dart';
import '../../domain/entities/pedido.dart';
import '../../domain/usecases/pedido_usecase.dart';

/// Línea del pedido que se está armando en la app (antes de enviarlo)
class LineaCarrito {
  final Item item;
  double cajas;
  double botellas;

  /// Nivel de precio elegido por el vendedor: pvp, ofe, may, dis o esp.
  /// El API recibe el nivel (no el monto) y busca el precio en la BD.
  String precioNivel;

  LineaCarrito({
    required this.item,
    this.cajas = 1,
    this.botellas = 0,
    this.precioNivel = 'pvp',
  });

  /// Precio unitario efectivo. Si el nivel guardado ya no tiene precio
  /// (Sabino lo puso en 0), cae al PVP para no mostrar $0.
  double get precioUnit {
    final p = item.precioDe(precioNivel);
    return p > 0 ? p : item.dolPre;
  }

  String get nivelNombre => Item.nombresNivel[precioNivel] ?? 'PVP';

  double get unidadTotal => cajas * item.cantunidad + botellas;
  double get total {
    final fraccion = item.cantunidad > 0 ? botellas / item.cantunidad : 0;
    return _round2((cajas + fraccion) * precioUnit);
  }

  Map<String, dynamic> toJson() => {
        'coditems': item.coditems,
        'cajas': cajas,
        'botellas': botellas,
        'precio_nivel': precioNivel,
      };
}

double _round2(double n) => (n * 100).roundToDouble() / 100;

class PedidosProvider extends ChangeNotifier {
  final GetPedidosUseCase _getPedidosUseCase;
  final GetPedidoDetalleUseCase _getPedidoDetalleUseCase;
  // ignore: unused_field
  final CrearPedidoUseCase _crearPedidoUseCase; // la creación va por OutboxSyncService
  final AnularPedidoUseCase _anularPedidoUseCase;
  final ActualizarPedidoUseCase _actualizarPedidoUseCase;

  PedidosProvider({
    required GetPedidosUseCase getPedidosUseCase,
    required GetPedidoDetalleUseCase getPedidoDetalleUseCase,
    required CrearPedidoUseCase crearPedidoUseCase,
    required AnularPedidoUseCase anularPedidoUseCase,
    required ActualizarPedidoUseCase actualizarPedidoUseCase,
  })  : _getPedidosUseCase = getPedidosUseCase,
        _getPedidoDetalleUseCase = getPedidoDetalleUseCase,
        _crearPedidoUseCase = crearPedidoUseCase,
        _anularPedidoUseCase = anularPedidoUseCase,
        _actualizarPedidoUseCase = actualizarPedidoUseCase;

  // === Lista ===
  List<Pedido> _pedidos = [];
  bool _estaCargandoLista = false;
  String? _errorLista;

  String? _filtroStatus;   // null = todos
  String? _filtroBuscar;

  // Pedidos guardados en el teléfono (pendientes de envío o con error)
  List<PedidoLocal> _pedidosLocales = [];
  List<PedidoLocal> get pedidosLocales => _pedidosLocales;

  List<Pedido> get pedidos => _pedidos;
  bool get estaCargandoLista => _estaCargandoLista;
  String? get errorLista => _errorLista;
  String? get filtroStatus => _filtroStatus;
  String? get filtroBuscar => _filtroBuscar;

  // === Detalle ===
  Pedido? _pedidoDetalle;
  bool _estaCargandoDetalle = false;
  String? _errorDetalle;

  Pedido? get pedidoDetalle => _pedidoDetalle;
  bool get estaCargandoDetalle => _estaCargandoDetalle;
  String? get errorDetalle => _errorDetalle;

  // === Carrito (pedido en construcción) ===
  Cliente? _clienteSeleccionado;
  final List<LineaCarrito> _carrito = [];
  String _observaciones = '';
  bool _estaEnviando = false;
  String? _errorEnviar;
  String? _editandoUid;   // != null cuando el carrito corresponde a un pedido existente (servidor)
  PedidoLocal? _editandoLocal; // != null cuando se edita un pedido guardado en el teléfono
  String? _mensajeUltimoEnvio; // texto para el snackbar tras enviar/guardar

  String? get editandoUid => _editandoUid;
  bool get enModoEdicion => _editandoUid != null || _editandoLocal != null;
  bool get enModoEdicionLocal => _editandoLocal != null;
  String? get mensajeUltimoEnvio => _mensajeUltimoEnvio;

  /// Título de la pantalla del carrito
  String get tituloCarrito {
    if (_editandoUid != null) return 'Editar #$_editandoUid';
    if (_editandoLocal != null) return 'Editar pedido guardado';
    return 'Nuevo pedido';
  }

  Cliente? get clienteSeleccionado => _clienteSeleccionado;
  List<LineaCarrito> get carrito => List.unmodifiable(_carrito);
  String get observaciones => _observaciones;
  bool get estaEnviando => _estaEnviando;
  String? get errorEnviar => _errorEnviar;
  double get totalCarrito =>
      _round2(_carrito.fold(0.0, (s, l) => s + l.total));
  bool get carritoListo => _clienteSeleccionado != null && _carrito.isNotEmpty;

  // === Anulación ===
  bool _estaAnulando = false;
  bool get estaAnulando => _estaAnulando;

  // ---------------------------------------------------------------- lista
  Future<void> cargarPedidos({String? status, String? buscar, bool mantenerFiltros = false}) async {
    if (!mantenerFiltros) {
      _filtroStatus = status;
      _filtroBuscar = buscar;
    }
    _estaCargandoLista = true;
    _errorLista = null;
    notifyListeners();

    await cargarLocales(notificar: false);

    try {
      _pedidos = await _getPedidosUseCase.execute(status: _filtroStatus, buscar: _filtroBuscar);
    } on NetworkException catch (e) {
      _errorLista = e.message;
    } on AppTimeoutException catch (e) {
      _errorLista = e.message;
    } on ServerException catch (e) {
      _errorLista = e.message;
    } catch (e) {
      _errorLista = 'Error al cargar pedidos';
    }

    _estaCargandoLista = false;
    notifyListeners();
  }

  /// Pedidos del teléfono (pendientes / con error), filtrados como la lista.
  Future<void> cargarLocales({bool notificar = true}) async {
    try {
      var lista = await OutboxSyncService.instance.listarVisibles();
      // Solo tienen sentido en "Todos" y "En proceso"
      if (_filtroStatus != null && _filtroStatus != Pedido.statusEnProceso) lista = [];
      final q = (_filtroBuscar ?? '').trim().toLowerCase();
      if (q.isNotEmpty) {
        lista = lista.where((p) => p.clienteNombre.toLowerCase().contains(q)).toList();
      }
      _pedidosLocales = lista;
    } catch (_) {
      _pedidosLocales = [];
    }
    if (notificar) notifyListeners();
  }

  // -------------------------------------------------------------- detalle
  Future<void> cargarDetalle(String uidPedido) async {
    _estaCargandoDetalle = true;
    _errorDetalle = null;
    _pedidoDetalle = null;
    notifyListeners();

    try {
      _pedidoDetalle = await _getPedidoDetalleUseCase.execute(uidPedido);
    } on NetworkException catch (e) {
      _errorDetalle = e.message;
    } on AppTimeoutException catch (e) {
      _errorDetalle = e.message;
    } on ServerException catch (e) {
      _errorDetalle = e.message;
    } catch (e) {
      _errorDetalle = 'Error al cargar el pedido';
    }

    _estaCargandoDetalle = false;
    notifyListeners();
  }

  void limpiarDetalle() {
    _pedidoDetalle = null;
    _errorDetalle = null;
  }

  // -------------------------------------------------------------- carrito
  void seleccionarCliente(Cliente cliente) {
    _clienteSeleccionado = cliente;
    notifyListeners();
  }

  void setObservaciones(String texto) {
    _observaciones = texto;
  }

  /// Agrega un producto; si ya está, suma una caja
  void agregarItem(Item item) {
    final idx = _carrito.indexWhere((l) => l.item.coditems == item.coditems);
    if (idx >= 0) {
      _carrito[idx].cajas += 1;
    } else {
      _carrito.add(LineaCarrito(item: item));
    }
    notifyListeners();
  }

  void actualizarLinea(String coditems, {double? cajas, double? botellas, String? precioNivel}) {
    final idx = _carrito.indexWhere((l) => l.item.coditems == coditems);
    if (idx < 0) return;
    final linea = _carrito[idx];
    if (precioNivel != null && linea.item.precioDe(precioNivel) > 0) {
      linea.precioNivel = precioNivel;
    }
    if (cajas != null) linea.cajas = cajas < 0 ? 0 : cajas;
    if (botellas != null) {
      final max = linea.item.cantunidad - 1;
      linea.botellas = botellas < 0 ? 0 : (botellas > max ? max : botellas);
    }
    notifyListeners();
  }

  void quitarLinea(String coditems) {
    _carrito.removeWhere((l) => l.item.coditems == coditems);
    notifyListeners();
  }

  void limpiarCarrito() {
    _clienteSeleccionado = null;
    _carrito.clear();
    _observaciones = '';
    _errorEnviar = null;
    _editandoUid = null;
    _editandoLocal = null;
    notifyListeners();
  }

  /// Carga un pedido guardado en el teléfono para editarlo (no requiere conexión).
  void cargarLocalEnCarrito(PedidoLocal pedido) {
    _carrito.clear();
    _editandoUid = null;
    _editandoLocal = pedido;
    _observaciones = pedido.observaciones;
    _errorEnviar = null;
    _clienteSeleccionado = pedido.toCliente();
    for (final l in pedido.lineas) {
      _carrito.add(LineaCarrito(
          item: l.toItem(), cajas: l.cajas, botellas: l.botellas, precioNivel: l.precioNivel));
    }
    notifyListeners();
  }

  Future<void> descartarLocal(String uuid) async {
    await OutboxSyncService.instance.descartar(uuid);
    await cargarLocales();
  }

  /// Reintenta un pedido con error. Devuelve el uid_pedido si se envió.
  Future<String?> reintentarLocal(String uuid) async {
    final r = await OutboxSyncService.instance.reintentar(uuid);
    await cargarLocales(notificar: false);
    if (r != null && r.enviado) {
      await cargarPedidos(mantenerFiltros: true);
      return r.pedido.uidPedido;
    }
    notifyListeners();
    return null;
  }

  /// Carga un pedido existente en el carrito para editarlo.
  /// Usa los datos actuales del producto que devuelve GET /pedidos/:id.
  void cargarEnCarrito(Pedido pedido) {
    _carrito.clear();
    _editandoUid = pedido.uidPedido;
    _observaciones = pedido.tieneObservaciones ? pedido.observaciones : '';
    _errorEnviar = null;
    // Cliente mínimo: la pantalla solo necesita nombre y uid
    _clienteSeleccionado = Cliente(
      uidCliente: pedido.uidCliente,
      codigo: '',
      cedula: '',
      tipoCedula: '',
      nombres: pedido.clienteNombre,
      apellidos: '',
      telefonoCelular: '',
      telefonoCasa: '',
      telefonoOficina: '',
      direccion: pedido.clienteDireccion,
      email: '',
      comentario: '',
      status: '',
    );
    for (final it in pedido.items) {
      final item = Item(
        coditems: it.coditems,
        desitems: it.descripcion,
        existencia: 0,
        ubicacion: '',
        codBarra: '',
        activo: it.activo ? '1' : '0',
        status: '',
        precioPvp: 0,
        precioEspecial: 0,
        precioDistribuidor: 0,
        precioMayor: 0,
        precioOferta: 0,
        ventaCaja: '1',
        ventaBotella: it.ventaBotella ? '1' : '0',
        litros: 0,
        codMarca: 0,
        codLinea: 0,
        codPresentacion: 0,
        nombreMarca: '',
        dolPre: it.dolPre > 0 ? it.dolPre : it.precunit,
        dolOfe: it.dolOfe,
        dolMay: it.dolMay,
        dolDis: it.dolDis,
        dolEsp: it.dolEsp,
        cantunidad: it.cantunidad,
        nombreLinea: it.nombreLinea,
        nombrePresentacion: it.nombrePresentacion,
      );
      _carrito.add(LineaCarrito(
          item: item,
          cajas: it.cantidad,
          botellas: it.cantidadUnidad,
          precioNivel: it.nivelDetectado));
    }
    notifyListeners();
  }

  /// Envía el carrito al API. Devuelve el uid_pedido creado o null si falló.
  Future<String?> enviarPedido() async {
    _estaEnviando = true;
    _errorEnviar = null;
    notifyListeners();

    // Líneas sin cantidad no se mandan
    final lineas = _carrito
        .where((l) => l.cajas > 0 || l.botellas > 0)
        .map((l) => l.toJson())
        .toList();

    try {
      // --- Edición de un pedido ya enviado: va directo a la API (requiere conexión) ---
      if (_editandoUid != null) {
        final resp = await _actualizarPedidoUseCase.execute(
          _editandoUid!,
          observaciones: _observaciones,
          items: lineas,
        );
        final uid = resp['uid_pedido']?.toString();
        _mensajeUltimoEnvio = 'Pedido #$uid actualizado';
        _estaEnviando = false;
        final editado = _editandoUid;
        limpiarCarrito();
        await cargarPedidos(mantenerFiltros: true);
        if (editado != null) await cargarDetalle(editado);
        return uid;
      }

      // --- Creación (o edición de un pedido local): SIEMPRE por el outbox ---
      final cliente = _clienteSeleccionado;
      if (cliente == null || cliente.uidCliente <= 0) throw ArgumentError('Debe seleccionar un cliente');
      if (lineas.isEmpty) throw ArgumentError('El pedido debe tener al menos un producto');

      final lineasLocales = _carrito
          .where((l) => l.cajas > 0 || l.botellas > 0)
          .map((l) => LineaLocal(
                coditems: l.item.coditems,
                descripcion: l.item.desitems,
                cajas: l.cajas,
                botellas: l.botellas,
                dolPre: l.precioUnit,
                precioNivel: l.precioNivel,
                cantunidad: l.item.cantunidad,
                ventaBotella: l.item.ventaBotella == '1',
                nombreLinea: l.item.nombreLinea,
                nombrePresentacion: l.item.nombrePresentacion,
              ))
          .toList();

      final ahora = DateTime.now();
      final ResultadoEnvio r;
      if (_editandoLocal != null) {
        r = await OutboxSyncService.instance.reemplazar(_editandoLocal!.copyWith(
          uidCliente: cliente.uidCliente,
          clienteNombre: cliente.nombreCompleto,
          observaciones: _observaciones.trim(),
          lineas: lineasLocales,
          fecmod: ahora,
        ));
      } else {
        r = await OutboxSyncService.instance.encolar(PedidoLocal(
          uuid: generarUuidV4(),
          uidVendedor: OutboxSyncService.instance.uidVendedor ?? '',
          uidCliente: cliente.uidCliente,
          clienteNombre: cliente.nombreCompleto,
          observaciones: _observaciones.trim(),
          lineas: lineasLocales,
          fecreg: ahora,
          fecmod: ahora,
        ));
      }

      if (r.enviado) {
        _mensajeUltimoEnvio = 'Pedido #${r.pedido.uidPedido} creado';
      } else if (r.fallido) {
        _mensajeUltimoEnvio = 'El servidor rechazó el pedido: ${r.pedido.ultimoError ?? ''}';
      } else {
        _mensajeUltimoEnvio = ConnectionMonitor.instance.intentarRemoto
            ? 'Pedido guardado en el teléfono, se enviará en breve'
            : 'Sin conexión: pedido guardado en el teléfono, se enviará al recuperar señal';
      }
      _estaEnviando = false;
      limpiarCarrito();
      await cargarPedidos(mantenerFiltros: true);
      return r.enviado ? r.pedido.uidPedido : r.pedido.uuid;
    } on ArgumentError catch (e) {
      _errorEnviar = e.message;
    } on ServerException catch (e) {
      _errorEnviar = e.message;
    } on NetworkException catch (e) {
      _errorEnviar = e.message;
    } on AppTimeoutException catch (e) {
      _errorEnviar = e.message;
    } catch (e) {
      _errorEnviar = 'Error al enviar el pedido';
    }

    _estaEnviando = false;
    notifyListeners();
    return null;
  }

  // ------------------------------------------------------------- anulación
  Future<bool> anularPedido(String uidPedido, {String? motivo}) async {
    _estaAnulando = true;
    notifyListeners();

    bool ok = false;
    try {
      await _anularPedidoUseCase.execute(uidPedido, motivo: motivo);
      ok = true;
    } on ServerException catch (e) {
      _errorDetalle = e.message;
    } on NetworkException catch (e) {
      _errorDetalle = e.message;
    } catch (e) {
      _errorDetalle = 'Error al anular el pedido';
    }

    _estaAnulando = false;
    if (ok) {
      await cargarDetalle(uidPedido);
      await cargarPedidos(mantenerFiltros: true);
    } else {
      notifyListeners();
    }
    return ok;
  }
}


/// UUID v4 con Random.secure (sin dependencia externa).
String generarUuidV4() {
  final rnd = Random.secure();
  final b = List<int>.generate(16, (_) => rnd.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40; // versión 4
  b[8] = (b[8] & 0x3f) | 0x80; // variante RFC 4122
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}
