import 'package:flutter/material.dart';
import '../../domain/entities/dashboard_data.dart';
import '../../domain/usecases/get_dashboard_usecase.dart';
import '../../../../core/errors/exceptions.dart';

class DashboardProvider extends ChangeNotifier {
  final GetDashboardUseCase _getDashboardUseCase;

  DashboardProvider({required GetDashboardUseCase getDashboardUseCase})
      : _getDashboardUseCase = getDashboardUseCase;

  // Estado
  DashboardData? _data;
  bool _estaCargando = false;
  String? _error;
  DateTime? _ultimaActualizacion;

  // Getters
  DashboardData? get data => _data;
  bool get estaCargando => _estaCargando;
  String? get error => _error;
  DateTime? get ultimaActualizacion => _ultimaActualizacion;

  /// Cargar datos del dashboard desde la API
  Future<void> cargarDashboard() async {
    _estaCargando = true;
    _error = null;
    notifyListeners();

    try {
      _data = await _getDashboardUseCase.execute();
      _ultimaActualizacion = DateTime.now();
    } on NetworkException catch (e) {
      _error = e.message;
    } on AppTimeoutException catch (e) {
      _error = e.message;
    } on UnauthorizedException catch (e) {
      _error = e.message;
    } on ServerException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Error al cargar el dashboard';
    }

    _estaCargando = false;
    notifyListeners();
  }
}