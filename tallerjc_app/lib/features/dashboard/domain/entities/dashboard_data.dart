/// Entidad con los datos del dashboard
class DashboardData {
  final int pedidosDia;
  final int pedidosPendientes;
  final int totalClientes;
  final int totalProductos;

  const DashboardData({
    required this.pedidosDia,
    required this.pedidosPendientes,
    required this.totalClientes,
    required this.totalProductos,
  });
}