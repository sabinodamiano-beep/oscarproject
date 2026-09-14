import '../../../../core/database/local_database.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/sync/catalog_sync_service.dart';
import '../../../../core/sync/connection_monitor.dart';
import '../../domain/entities/cliente.dart';
import '../../domain/repositories/cliente_repository.dart';
import '../datasources/cliente_remote_datasource.dart';
import '../models/cliente_model.dart';

/// Estrategia: API primero; si falla por red/timeout (o ya sabemos que no hay
/// conexión), caché local SQLite. La creación de clientes exige conexión.
class ClientesRepositoryImpl implements ClientesRepository {
  final ClientesRemoteDatasource _remoteDatasource;
  final LocalDatabase _local = LocalDatabase.instance;
  final ConnectionMonitor _monitor = ConnectionMonitor.instance;
  final CatalogSyncService _sync = CatalogSyncService.instance;

  ClientesRepositoryImpl({ClientesRemoteDatasource? remoteDatasource})
      : _remoteDatasource = remoteDatasource ?? ClientesRemoteDatasource();

  @override
  Future<List<Cliente>> getClientes({String? buscar}) async {
    if (_monitor.intentarRemoto) {
      try {
        return await _remoteDatasource.getClientes(buscar: buscar);
      } on NetworkException {
        _monitor.marcarCaida();
      } on AppTimeoutException {
        _monitor.marcarCaida();
      }
    }
    _exigirCacheVigente();
    final filas = await _local.buscarClientes(buscar: buscar);
    return filas.map(ClienteModel.fromJson).toList();
  }

  @override
  Future<Cliente> getClienteDetalle(int uidCliente) async {
    if (_monitor.intentarRemoto) {
      try {
        return await _remoteDatasource.getClienteDetalle(uidCliente);
      } on NetworkException {
        _monitor.marcarCaida();
      } on AppTimeoutException {
        _monitor.marcarCaida();
      }
    }
    _exigirCacheVigente();
    final fila = await _local.getCliente(uidCliente);
    if (fila == null) {
      throw ServerException(message: 'Cliente no encontrado en los datos guardados', statusCode: 404);
    }
    return ClienteModel.fromJson(fila);
  }

  @override
  Future<Map<String, dynamic>> crearCliente({
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
    // Decisión D2: no se crean clientes sin conexión.
    if (!_monitor.intentarRemoto) {
      throw NetworkException(message: 'Crear clientes requiere conexión. Intenta cuando tengas señal.');
    }
    final datos = ClienteModel.toCreateJson(
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
    return await _remoteDatasource.crearCliente(datos);
  }

  void _exigirCacheVigente() {
    if (!_local.abierta || !_sync.cacheVigente) throw _sync.sinDatosLocales();
  }
}
