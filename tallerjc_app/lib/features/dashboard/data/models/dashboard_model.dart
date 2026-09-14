import '../../domain/entities/dashboard_data.dart';

class DashboardModel extends DashboardData {
  const DashboardModel({
    required super.pedidosDia,
    required super.pedidosPendientes,
    required super.totalClientes,
    required super.totalProductos,
  });

  /// Desde JSON del endpoint GET /api/dashboard
  factory DashboardModel.fromJson(Map<String, dynamic> json) {
    return DashboardModel(
      pedidosDia: json['pedidos_dia'] ?? 0,
      pedidosPendientes: json['pedidos_pendientes'] ?? 0,
      totalClientes: json['total_clientes'] ?? 0,
      totalProductos: json['total_productos'] ?? 0,
    );
  }
}