import '../entities/dashboard_data.dart';
import '../repositories/dashboard_repository.dart';

class GetDashboardUseCase {
  final DashboardRepository _repository;

  GetDashboardUseCase({required DashboardRepository repository})
      : _repository = repository;

  Future<DashboardData> execute() async {
    return await _repository.getDashboard();
  }
}