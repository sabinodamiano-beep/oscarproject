import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../models/dashboard_model.dart';

class DashboardRemoteDatasource {
  final ApiClient _apiClient;

  DashboardRemoteDatasource({ApiClient? apiClient})
      : _apiClient = apiClient ?? ApiClient();

  Future<DashboardModel> getDashboard() async {
    final response = await _apiClient.get(ApiConstants.dashboard);
    return DashboardModel.fromJson(response);
  }
}