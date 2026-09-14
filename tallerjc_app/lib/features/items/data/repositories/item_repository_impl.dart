import '../../../../core/database/local_database.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/sync/catalog_sync_service.dart';
import '../../../../core/sync/connection_monitor.dart';
import '../../domain/entities/item.dart';
import '../../domain/entities/marca.dart';
import '../../domain/repositories/item_repository.dart';
import '../datasources/item_remote_datasource.dart';
import '../models/item_model.dart';

/// Estrategia: API primero; si falla por red/timeout (o ya sabemos que no hay
/// conexión), caché local SQLite. Las marcas no se cachean (tbl_marca está
/// corrupta y la app no depende de ella): sin conexión devuelve lista vacía.
class ItemsRepositoryImpl implements ItemsRepository {
  final ItemsRemoteDatasource _remoteDatasource;
  final LocalDatabase _local = LocalDatabase.instance;
  final ConnectionMonitor _monitor = ConnectionMonitor.instance;
  final CatalogSyncService _sync = CatalogSyncService.instance;

  ItemsRepositoryImpl({ItemsRemoteDatasource? remoteDatasource})
      : _remoteDatasource = remoteDatasource ?? ItemsRemoteDatasource();

  @override
  Future<List<Item>> getItems({String? buscar, String? linea}) async {
    if (_monitor.intentarRemoto) {
      try {
        return await _remoteDatasource.getItems(buscar: buscar, linea: linea);
      } on NetworkException {
        _monitor.marcarCaida();
      } on AppTimeoutException {
        _monitor.marcarCaida();
      }
    }
    _exigirCacheVigente();
    final filas = await _local.buscarItems(buscar: buscar, linea: linea);
    return filas.map(ItemModel.fromJson).toList();
  }

  @override
  Future<Item> getItemDetalle(String coditems) async {
    if (_monitor.intentarRemoto) {
      try {
        return await _remoteDatasource.getItemDetalle(coditems);
      } on NetworkException {
        _monitor.marcarCaida();
      } on AppTimeoutException {
        _monitor.marcarCaida();
      }
    }
    _exigirCacheVigente();
    final fila = await _local.getItem(coditems);
    if (fila == null) {
      throw ServerException(message: 'Producto no encontrado en los datos guardados', statusCode: 404);
    }
    return ItemModel.fromJson(fila);
  }

  @override
  Future<List<String>> getLineas() async {
    if (_monitor.intentarRemoto) {
      try {
        return await _remoteDatasource.getLineas();
      } on NetworkException {
        _monitor.marcarCaida();
      } on AppTimeoutException {
        _monitor.marcarCaida();
      }
    }
    _exigirCacheVigente();
    return await _local.lineasLocales();
  }

  @override
  Future<List<Marca>> getMarcas() async {
    if (!_monitor.intentarRemoto) return const [];
    try {
      return await _remoteDatasource.getMarcas();
    } on NetworkException {
      _monitor.marcarCaida();
      return const [];
    } on AppTimeoutException {
      _monitor.marcarCaida();
      return const [];
    }
  }

  void _exigirCacheVigente() {
    if (!_local.abierta || !_sync.cacheVigente) throw _sync.sinDatosLocales();
  }
}
