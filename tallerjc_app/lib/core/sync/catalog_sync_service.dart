import 'package:flutter/foundation.dart';

import '../constants/api_constants.dart';
import '../database/local_database.dart';
import '../errors/exceptions.dart';
import '../network/api_client.dart';
import 'connection_monitor.dart';

/// Descarga los catálogos completos (clientes y productos) al caché local y
/// lleva la marca de tiempo de la última sincronización.
///
/// Regla acordada (D3): el caché vale **máximo 24 horas**. Después de eso la
/// app no sirve datos locales y pide conectarse. El objetivo del offline es
/// cubrir pérdidas de señal, no jornadas enteras sin sincronizar.
class CatalogSyncService extends ChangeNotifier {
  CatalogSyncService._();
  static final CatalogSyncService instance = CatalogSyncService._();

  static const Duration validezCache = Duration(hours: 24);

  /// Si el caché tiene más de esto y hay conexión, se refresca solo al abrir la app.
  static const Duration refrescoAutomatico = Duration(hours: 1);

  static const String _metaUltimaSync = 'ultima_sync_catalogos';
  static const String _metaClientes = 'total_clientes';
  static const String _metaItems = 'total_items';

  final ApiClient _api = ApiClient();
  final LocalDatabase _local = LocalDatabase.instance;

  DateTime? _ultimaSync;
  int _totalClientes = 0;
  int _totalItems = 0;
  bool _sincronizando = false;
  String? _error;

  DateTime? get ultimaSync => _ultimaSync;
  int get totalClientes => _totalClientes;
  int get totalItems => _totalItems;
  bool get sincronizando => _sincronizando;
  String? get error => _error;
  String? get empresa => _local.empresa;

  bool get hayCache => _ultimaSync != null && (_totalClientes > 0 || _totalItems > 0);
  Duration? get edadCache => _ultimaSync == null ? null : DateTime.now().difference(_ultimaSync!);
  bool get cacheVigente => hayCache && edadCache! <= validezCache;

  /// Abre la base de la empresa y carga las marcas de tiempo. Llamar al
  /// iniciar sesión (login o sesión restaurada) ANTES de usar los repositorios.
  Future<void> preparar(String codEmpresa) async {
    await _local.abrir(codEmpresa);
    final ts = await _local.getMeta(_metaUltimaSync);
    _ultimaSync = ts == null ? null : DateTime.tryParse(ts);
    _totalClientes = int.tryParse(await _local.getMeta(_metaClientes) ?? '') ?? 0;
    _totalItems = int.tryParse(await _local.getMeta(_metaItems) ?? '') ?? 0;
    _error = null;
    notifyListeners();
  }

  /// Cierra la base local (logout). El archivo se conserva para el próximo
  /// login de la misma empresa en este teléfono.
  Future<void> cerrar() async {
    await _local.cerrar();
    _ultimaSync = null;
    _totalClientes = 0;
    _totalItems = 0;
    notifyListeners();
  }

  /// Sincroniza si no hay caché o si es más viejo que [refrescoAutomatico].
  /// No lanza excepciones: si no hay red simplemente no hace nada.
  Future<void> sincronizarSiHaceFalta() async {
    if (!_local.abierta) return;
    final edad = edadCache;
    if (hayCache && edad != null && edad < refrescoAutomatico) return;
    if (!ConnectionMonitor.instance.intentarRemoto) return;
    await sincronizar();
  }

  /// Descarga completa de ambos catálogos y reemplazo atómico.
  /// Devuelve true si terminó bien. El error queda en [error].
  Future<bool> sincronizar() async {
    if (_sincronizando || !_local.abierta) return false;
    _sincronizando = true;
    _error = null;
    notifyListeners();

    try {
      final clientes = await _api.get('${ApiConstants.clientes}?todos=1') as List;
      final items = await _api.get('${ApiConstants.productos}?todos=1') as List;

      _totalClientes = await _local.reemplazarClientes(clientes);
      _totalItems = await _local.reemplazarItems(items);
      _ultimaSync = DateTime.now();

      await _local.setMeta(_metaUltimaSync, _ultimaSync!.toIso8601String());
      await _local.setMeta(_metaClientes, '$_totalClientes');
      await _local.setMeta(_metaItems, '$_totalItems');

      ConnectionMonitor.instance.verificar();
      return true;
    } on NetworkException catch (e) {
      _error = e.message;
      ConnectionMonitor.instance.marcarCaida();
    } on AppTimeoutException catch (e) {
      _error = e.message;
      ConnectionMonitor.instance.marcarCaida();
    } on UnauthorizedException catch (e) {
      _error = e.message;
    } on ServerException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Error al sincronizar: $e';
    } finally {
      _sincronizando = false;
      notifyListeners();
    }
    return false;
  }

  /// Mensaje para cuando se pide dato local y no se puede servir.
  NetworkException sinDatosLocales() {
    if (!hayCache) {
      return NetworkException(
          message: 'Sin conexión y sin datos guardados. Conéctate para sincronizar.');
    }
    return NetworkException(
        message: 'Sin conexión y los datos guardados tienen más de 24 h. Conéctate para sincronizar.');
  }
}
