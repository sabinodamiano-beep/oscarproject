import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:gyfsoftware_movil/features/clientes/data/repositories/cliente_repository_impl.dart';
import 'package:gyfsoftware_movil/features/clientes/domain/usecases/cliente_usecase.dart';
import 'package:gyfsoftware_movil/features/clientes/presentation/providers/cliente_provider.dart';
import 'package:gyfsoftware_movil/features/items/data/repositories/item_repository_impl.dart';
import 'package:gyfsoftware_movil/features/items/domain/usecases/item_usecase.dart';
import 'package:gyfsoftware_movil/features/items/presentation/providers/item_provider.dart';
import 'package:gyfsoftware_movil/features/pedidos/data/repositories/pedido_repository_impl.dart';
import 'package:gyfsoftware_movil/features/pedidos/domain/usecases/pedido_usecase.dart';
import 'package:gyfsoftware_movil/features/pedidos/presentation/providers/pedido_provider.dart';
import 'app.dart';
import 'core/network/api_client.dart';
import 'core/sync/connection_monitor.dart';
import 'features/auth/data/repositories/auth_repository_impl.dart';
import 'features/auth/domain/usecases/login_usecase.dart';
import 'features/auth/presentation/providers/auth_provider.dart';
import 'features/dashboard/data/repositories/dashboard_repository_impl.dart';
import 'features/dashboard/domain/usecases/get_dashboard_usecase.dart';
import 'features/dashboard/presentation/providers/dashboard_provider.dart';


void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Estado global de conexión (red + ping real al servidor)
  ConnectionMonitor.instance.iniciar();

  // Repositorios
  final authRepository = AuthRepositoryImpl();
  final dashboardRepository = DashboardRepositoryImpl();
  final clientesRepository = ClientesRepositoryImpl();
  final itemsRepository = ItemsRepositoryImpl();
  final pedidosRepository = PedidosRepositoryImpl();

  // Use cases
  final loginUseCase = LoginUseCase(repository: authRepository);
  final getDashboardUseCase = GetDashboardUseCase(repository: dashboardRepository);
  final getClientesUseCase = GetClientesUseCase(repository: clientesRepository);
  final getClienteDetalleUseCase = GetClienteDetalleUseCase(repository: clientesRepository);
  final crearClienteUseCase = CrearClienteUseCase(repository: clientesRepository);
  final getItemsUseCase = GetItemsUseCase(repository: itemsRepository);
  final getItemDetalleUseCase = GetItemDetalleUseCase(repository: itemsRepository);
  final getMarcasUseCase = GetMarcasUseCase(repository: itemsRepository);
  final getLineasUseCase = GetLineasUseCase(repository: itemsRepository);
  final getPedidosUseCase = GetPedidosUseCase(repository: pedidosRepository);
  final getPedidoDetalleUseCase = GetPedidoDetalleUseCase(repository: pedidosRepository);
  final crearPedidoUseCase = CrearPedidoUseCase(repository: pedidosRepository);
  final anularPedidoUseCase = AnularPedidoUseCase(repository: pedidosRepository);
  final actualizarPedidoUseCase = ActualizarPedidoUseCase(repository: pedidosRepository);

  // Auth provider (lo necesitamos antes para el callback de sesión expirada)
  final authProvider = AuthProvider(
    loginUseCase: loginUseCase,
    authRepository: authRepository,
  );

  // Configurar callback de sesión expirada → logout automático
  ApiClient().onSessionExpired = () {
    authProvider.logout();
  };

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authProvider),
        ChangeNotifierProvider(
          create: (_) => DashboardProvider(
            getDashboardUseCase: getDashboardUseCase,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => ClientesProvider(
            getClientesUseCase: getClientesUseCase,
            getClienteDetalleUseCase: getClienteDetalleUseCase,
            crearClienteUseCase: crearClienteUseCase,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => ItemsProvider(
            getItemsUseCase: getItemsUseCase,
            getItemDetalleUseCase: getItemDetalleUseCase,
            getMarcasUseCase: getMarcasUseCase,
            getLineasUseCase: getLineasUseCase,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => PedidosProvider(
            getPedidosUseCase: getPedidosUseCase,
            getPedidoDetalleUseCase: getPedidoDetalleUseCase,
            crearPedidoUseCase: crearPedidoUseCase,
            anularPedidoUseCase: anularPedidoUseCase,
            actualizarPedidoUseCase: actualizarPedidoUseCase,
          ),
        ),
      ],
      child: const GyfSoftwareApp(),
    ),
  );
}