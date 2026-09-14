import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/constants/api_constants.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/providers/auth_provider.dart';
import 'features/auth/presentation/screens/login_screen.dart';
import 'features/auth/presentation/screens/home_screen.dart';

class GyfSoftwareApp extends StatelessWidget {
  const GyfSoftwareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: ApiConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const _AppStartup(),
    );
  }
}

/// Verifica la sesión al iniciar y redirige al login o al home
class _AppStartup extends StatefulWidget {
  const _AppStartup();

  @override
  State<_AppStartup> createState() => _AppStartupState();
}

class _AppStartupState extends State<_AppStartup> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuthProvider>().verificarSesion();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, _) {
        if (authProvider.estaCargando) {
          return const _SplashScreen();
        }

        if (authProvider.estaAutenticado) {
          return const HomeScreen();
        }

        return const LoginScreen();
      },
    );
  }
}

/// Splash mientras verifica sesión
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/images/logo_login_card.png',
              width: 260,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 4),
            const Text(
              'Pedidos para vendedores',
              style: TextStyle(
                fontSize: 14,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 32),
            const CircularProgressIndicator(color: AppTheme.primary),
          ],
        ),
      ),
    );
  }
}