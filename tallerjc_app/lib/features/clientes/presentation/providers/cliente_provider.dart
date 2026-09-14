import 'package:flutter/material.dart';
import 'package:gyfsoftware_movil/features/clientes/domain/usecases/cliente_usecase.dart';
import '../../domain/entities/cliente.dart';
import '../../../../core/errors/exceptions.dart';

class ClientesProvider extends ChangeNotifier {
  final GetClientesUseCase _getClientesUseCase;
  final GetClienteDetalleUseCase _getClienteDetalleUseCase;
  final CrearClienteUseCase _crearClienteUseCase;

  ClientesProvider({
    required GetClientesUseCase getClientesUseCase,
    required GetClienteDetalleUseCase getClienteDetalleUseCase,
    required CrearClienteUseCase crearClienteUseCase,
  })  : _getClientesUseCase = getClientesUseCase,
        _getClienteDetalleUseCase = getClienteDetalleUseCase,
        _crearClienteUseCase = crearClienteUseCase;

  // === Estado de lista ===
  List<Cliente> _clientes = [];
  bool _estaCargandoLista = false;
  String? _errorLista;

  List<Cliente> get clientes => _clientes;
  bool get estaCargandoLista => _estaCargandoLista;
  String? get errorLista => _errorLista;

  // === Estado de detalle ===
  Cliente? _clienteDetalle;
  bool _estaCargandoDetalle = false;
  String? _errorDetalle;

  Cliente? get clienteDetalle => _clienteDetalle;
  bool get estaCargandoDetalle => _estaCargandoDetalle;
  String? get errorDetalle => _errorDetalle;

  // === Estado de creación ===
  bool _estaCreando = false;
  String? _errorCrear;

  bool get estaCreando => _estaCreando;
  String? get errorCrear => _errorCrear;

  /// Cargar lista de clientes con búsqueda opcional
  Future<void> cargarClientes({String? buscar}) async {
    _estaCargandoLista = true;
    _errorLista = null;
    notifyListeners();

    try {
      _clientes = await _getClientesUseCase.execute(buscar: buscar);
    } on NetworkException catch (e) {
      _errorLista = e.message;
    } on AppTimeoutException catch (e) {
      _errorLista = e.message;
    } on ServerException catch (e) {
      _errorLista = e.message;
    } catch (e) {
      _errorLista = 'Error al cargar clientes';
    }

    _estaCargandoLista = false;
    notifyListeners();
  }

  /// Cargar detalle de un cliente
  Future<void> cargarDetalle(int uidCliente) async {
    _estaCargandoDetalle = true;
    _errorDetalle = null;
    _clienteDetalle = null;
    notifyListeners();

    try {
      _clienteDetalle = await _getClienteDetalleUseCase.execute(uidCliente);
    } on NetworkException catch (e) {
      _errorDetalle = e.message;
    } on ServerException catch (e) {
      _errorDetalle = e.message;
    } catch (e) {
      _errorDetalle = 'Error al cargar detalle del cliente';
    }

    _estaCargandoDetalle = false;
    notifyListeners();
  }

  /// Crear un cliente nuevo
  Future<bool> crearCliente({
    required String tipoCedula,
    required String cedula,
    required String nombres,
    required String apellidos,
    required String telefonoCelular,
    String? telefonoCasa,
    String? telefonoOficina,
    String? direccion,
    String? email,
    String? comentario,
  }) async {
    _estaCreando = true;
    _errorCrear = null;
    notifyListeners();

    try {
      await _crearClienteUseCase.execute(
        tipoCedula: tipoCedula,
        cedula: cedula,
        nombres: nombres,
        apellidos: apellidos,
        telefonoCelular: telefonoCelular,
        telefonoCasa: telefonoCasa,
        telefonoOficina: telefonoOficina,
        direccion: direccion,
        email: email,
        comentario: comentario,
      );
      _estaCreando = false;
      notifyListeners();
      return true;
    } on ServerException catch (e) {
      _errorCrear = e.message;
    } on NetworkException catch (e) {
      _errorCrear = e.message;
    } on ArgumentError catch (e) {
      _errorCrear = e.message;
    } catch (e) {
      _errorCrear = 'Error al crear cliente';
    }

    _estaCreando = false;
    notifyListeners();
    return false;
  }

  /// Limpiar detalle al salir
  void limpiarDetalle() {
    _clienteDetalle = null;
    _errorDetalle = null;
  }
}