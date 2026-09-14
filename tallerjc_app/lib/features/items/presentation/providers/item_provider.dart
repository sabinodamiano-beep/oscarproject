import 'package:flutter/material.dart';
import 'package:gyfsoftware_movil/features/items/domain/usecases/item_usecase.dart';
import '../../domain/entities/item.dart';
import '../../domain/entities/marca.dart';
import '../../../../core/errors/exceptions.dart';

class ItemsProvider extends ChangeNotifier {
  final GetItemsUseCase _getItemsUseCase;
  final GetItemDetalleUseCase _getItemDetalleUseCase;
  final GetMarcasUseCase _getMarcasUseCase;
  final GetLineasUseCase _getLineasUseCase;

  ItemsProvider({
    required GetItemsUseCase getItemsUseCase,
    required GetItemDetalleUseCase getItemDetalleUseCase,
    required GetMarcasUseCase getMarcasUseCase,
    required GetLineasUseCase getLineasUseCase,
  })  : _getItemsUseCase = getItemsUseCase,
        _getItemDetalleUseCase = getItemDetalleUseCase,
        _getMarcasUseCase = getMarcasUseCase,
        _getLineasUseCase = getLineasUseCase;

  // === Líneas (categorías) ===
  List<String> _lineas = [];
  String? _filtroLinea;
  List<String> get lineas => _lineas;
  String? get filtroLinea => _filtroLinea;

  // === Estado de lista ===
  List<Item> _items = [];
  bool _estaCargandoLista = false;
  String? _errorLista;

  List<Item> get items => _items;
  bool get estaCargandoLista => _estaCargandoLista;
  String? get errorLista => _errorLista;

  // === Estado de detalle ===
  Item? _itemDetalle;
  bool _estaCargandoDetalle = false;
  String? _errorDetalle;

  Item? get itemDetalle => _itemDetalle;
  bool get estaCargandoDetalle => _estaCargandoDetalle;
  String? get errorDetalle => _errorDetalle;

  // === Estado de marcas ===
  List<Marca> _marcas = [];
  bool _marcasCargadas = false;

  List<Marca> get marcas => _marcas;
  bool get marcasCargadas => _marcasCargadas;

  /// Cargar lista de productos con búsqueda opcional
  Future<void> cargarItems({String? buscar, String? linea, bool mantenerLinea = true}) async {
    if (!mantenerLinea || linea != null) _filtroLinea = linea;
    _estaCargandoLista = true;
    _errorLista = null;
    notifyListeners();

    try {
      _items = await _getItemsUseCase.execute(buscar: buscar, linea: _filtroLinea);
    } on NetworkException catch (e) {
      _errorLista = e.message;
    } on AppTimeoutException catch (e) {
      _errorLista = e.message;
    } on ServerException catch (e) {
      _errorLista = e.message;
    } catch (e) {
      _errorLista = 'Error al cargar productos';
    }

    _estaCargandoLista = false;
    notifyListeners();
  }

  /// Cargar detalle de un producto
  Future<void> cargarDetalle(String coditems) async {
    _estaCargandoDetalle = true;
    _errorDetalle = null;
    _itemDetalle = null;
    notifyListeners();

    try {
      _itemDetalle = await _getItemDetalleUseCase.execute(coditems);
    } on NetworkException catch (e) {
      _errorDetalle = e.message;
    } on ServerException catch (e) {
      _errorDetalle = e.message;
    } catch (e) {
      _errorDetalle = 'Error al cargar detalle del producto';
    }

    _estaCargandoDetalle = false;
    notifyListeners();
  }

  /// Cargar líneas (una sola vez)
  Future<void> cargarLineas() async {
    if (_lineas.isNotEmpty) return;
    try {
      _lineas = await _getLineasUseCase.execute();
    } catch (_) {
      // No es crítico
    }
    notifyListeners();
  }

  /// Cambiar filtro de línea y recargar
  Future<void> filtrarPorLinea(String? linea, {String? buscar}) async {
    _filtroLinea = linea;
    await cargarItems(buscar: buscar);
  }

  /// Cargar marcas
  Future<void> cargarMarcas() async {
    if (_marcasCargadas) return;

    try {
      _marcas = await _getMarcasUseCase.execute();
      _marcasCargadas = true;
    } catch (_) {
      // No es crítico
    }
    notifyListeners();
  }

  /// Limpiar detalle al salir
  void limpiarDetalle() {
    _itemDetalle = null;
    _errorDetalle = null;
  }
}