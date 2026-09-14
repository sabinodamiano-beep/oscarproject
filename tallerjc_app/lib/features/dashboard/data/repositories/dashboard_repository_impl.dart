import 'dart:convert';

import '../../../../core/database/local_database.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/sync/catalog_sync_service.dart';
import '../../../../core/sync/connection_monitor.dart';
import '../../domain/entities/dashboard_data.dart';
import '../../domain/repositories/dashboard_repository.dart';
import '../datasources/dashboard_remote_datasource.dart';
import '../models/dashboard_model.dart';

/// Con conexión: API (y se guarda copia). Sin conexión: último dashboard
/// guardado; si nunca se guardó, se arma uno con los conteos del caché local
/// para no mostrar todo en cero.
class DashboardRepositoryImpl implements DashboardRepository {
  final DashboardRemoteDatasource _remoteDatasource;
  final LocalDatabase _local = LocalDatabase.instance;
  final ConnectionMonitor _monitor = ConnectionMonitor.instance;

  static const String _clave = 'dashboard_ultimo';

  DashboardRepositoryImpl({DashboardRemoteDatasource? remoteDatasource})
      : _remoteDatasource = remoteDatasource ?? DashboardRemoteDatasource();

  @override
  Future<DashboardData> getDashboard() async {
    if (_monitor.intentarRemoto) {
      try {
        final data = await _remoteDatasource.getDashboard();
        _guardar(data);
        return data;
      } on NetworkException {
        _monitor.marcarCaida();
      } on AppTimeoutException {
        _monitor.marcarCaida();
      }
    }
    return _local.abierta ? await _dashboardLocal() : throw NetworkException();
  }

  Future<void> _guardar(DashboardData d) async {
    if (!_local.abierta) return;
    try {
      await _local.setMeta(
          _clave,
          jsonEncode({
            'pedidos_dia': d.pedidosDia,
            'pedidos_pendientes': d.pedidosPendientes,
            'total_clientes': d.totalClientes,
            'total_productos': d.totalProductos,
          }));
    } catch (_) {}
  }

  Future<DashboardData> _dashboardLocal() async {
    final json = await _local.getMeta(_clave);
    if (json != null) {
      return DashboardModel.fromJson(Map<String, dynamic>.from(jsonDecode(json) as Map));
    }
    // Nunca se guardó: al menos mostrar lo que hay en el caché de catálogos.
    final sync = CatalogSyncService.instance;
    if (!sync.hayCache) {
      throw NetworkException(message: 'Sin conexión y sin datos guardados.');
    }
    return DashboardModel(
      pedidosDia: 0,
      pedidosPendientes: 0,
      totalClientes: sync.totalClientes,
      totalProductos: sync.totalItems,
    );
  }
}
