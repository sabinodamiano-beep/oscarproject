import 'package:flutter/material.dart';
import '../../domain/entities/vendedor.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/usecases/login_usecase.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/sync/catalog_sync_service.dart';
import '../../../../core/sync/cobros_outbox_service.dart';
import '../../../../core/sync/outbox_sync_service.dart';

class AuthProvider extends ChangeNotifier {
  final LoginUseCase _loginUseCase;
  final AuthRepository _authRepository;

  AuthProvider({
    required LoginUseCase loginUseCase,
    required AuthRepository authRepository,
  })  : _loginUseCase = loginUseCase,
        _authRepository = authRepository;

  // Estado
  Vendedor? _vendedor;
  bool _estaCargando = false;
  bool _estaAutenticado = false;
  String? _error;
  List<Map<String, dynamic>> _empresas = [];
  bool _cargandoEmpresas = false;

  // Getters
  Vendedor? get vendedor => _vendedor;
  bool get estaCargando => _estaCargando;
  bool get estaAutenticado => _estaAutenticado;
  String? get error => _error;
  List<Map<String, dynamic>> get empresas => _empresas;
  bool get cargandoEmpresas => _cargandoEmpresas;

  /// Cargar la lista de empresas desde la API (para el selector del login).
  /// Si falla (sin conexión), la lista queda vacía y el login muestra
  /// un campo de texto para escribir el código manualmente.
  Future<void> cargarEmpresas() async {
    _cargandoEmpresas = true;
    notifyListeners();

    try {
      _empresas = await _authRepository.getEmpresas();
    } catch (_) {
      _empresas = [];
    }

    _cargandoEmpresas = false;
    notifyListeners();
  }

  /// Verificar si hay sesión activa al iniciar la app
  Future<void> verificarSesion() async {
    _estaCargando = true;
    _error = null;
    notifyListeners();

    try {
      final haySession = await _authRepository.haySesionActiva();
      if (haySession) {
        _vendedor = await _authRepository.getVendedorGuardado();
        _estaAutenticado = _vendedor != null;
      }
      if (_estaAutenticado) await _prepararCacheLocal(refrescar: false);
    } catch (_) {
      _estaAutenticado = false;
    }

    _estaCargando = false;
    notifyListeners();
  }

  /// Iniciar sesión
  Future<bool> login(String empresa, String cedula, String password) async {
    _estaCargando = true;
    _error = null;
    notifyListeners();

    try {
      _vendedor = await _loginUseCase.execute(empresa, cedula, password);
      _estaAutenticado = true;
      // Guardar el nombre del tenant para documentos (PDF de pedidos)
      final emp = _empresas.where((e) => e['codigo'] == empresa).toList();
      if (emp.isNotEmpty) {
        await _authRepository
            .guardarEmpresaNombre((emp.first['nombre'] ?? '').toString());
      }
      await _prepararCacheLocal(refrescar: true);
      _estaCargando = false;
      notifyListeners();
      return true;
    } on ServerException catch (e) {
      _error = e.message;
    } on NetworkException catch (e) {
      _error = e.message;
    } on UnauthorizedException catch (e) {
      _error = e.message;
    } on AppTimeoutException catch (e) {
      _error = e.message;
    } on ArgumentError catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Error inesperado: $e';
    }

    _estaCargando = false;
    notifyListeners();
    return false;
  }

  /// Abre la base local de la empresa y dispara la sincronización de catálogos
  /// en segundo plano. Nunca bloquea el login: si no hay red, el sync
  /// simplemente no ocurre y se usa lo que haya en caché.
  Future<void> _prepararCacheLocal({required bool refrescar}) async {
    final empresa = await _authRepository.getEmpresaGuardada();
    if (empresa == null || empresa.isEmpty) return;
    try {
      await CatalogSyncService.instance.preparar(empresa);
    } catch (_) {
      return; // sin base local no hay offline, pero la app sigue funcionando online
    }
    // Cola de pedidos del vendedor (envía lo que haya quedado pendiente)
    final uidVendedor = _vendedor?.uidVendedor;
    if (uidVendedor != null && uidVendedor.isNotEmpty) {
      OutboxSyncService.instance.iniciar(uidVendedor);
      CobrosOutboxService.instance.iniciar(uidVendedor);
    }
    // Login explícito: sincronizar siempre. Sesión restaurada: solo si hace falta.
    if (refrescar) {
      CatalogSyncService.instance.sincronizar();
    } else {
      CatalogSyncService.instance.sincronizarSiHaceFalta();
    }
  }

  /// Cerrar sesión
  Future<void> logout() async {
    OutboxSyncService.instance.detener();
    CobrosOutboxService.instance.detener();
    await CatalogSyncService.instance.cerrar();
    await _authRepository.logout();
    _vendedor = null;
    _estaAutenticado = false;
    _error = null;
    notifyListeners();
  }

  /// Empresa usada en la última sesión (para preseleccionar en el login)
  Future<String?> getEmpresaRecordada() async {
    return await _authRepository.getEmpresaGuardada();
  }

  /// Nombre de la empresa (tenant) para mostrar en documentos (PDF)
  Future<String> getEmpresaNombre() async {
    return await _authRepository.getEmpresaNombre();
  }

  /// Guardar cédula para "Recordar usuario"
  Future<void> guardarCedulaRecordada(String cedula) async {
    await _authRepository.guardarCedulaRecordada(cedula);
  }

  /// Obtener cédula guardada
  Future<String?> getCedulaRecordada() async {
    return await _authRepository.getCedulaRecordada();
  }

  /// Limpiar cédula recordada
  Future<void> limpiarCedulaRecordada() async {
    await _authRepository.limpiarCedulaRecordada();
  }

  /// Limpiar error
  void limpiarError() {
    _error = null;
    notifyListeners();
  }
}
