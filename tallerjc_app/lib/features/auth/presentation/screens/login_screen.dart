import 'dart:async';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:provider/provider.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../providers/auth_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _cedulaController = TextEditingController();
  final _passwordController = TextEditingController();
  final _empresaManualController = TextEditingController();
  String? _empresaSeleccionada;
  bool _ocultarPassword = true;
  bool _recordarUsuario = false;
  bool _isConnected = true;
  bool? _servidorOk; // null = verificando
  StreamSubscription? _connectivitySubscription;

    @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _cargarDatosIniciales();
      _verificarConexion();
    });
  }

  Future<void> _cargarDatosIniciales() async {
    final authProvider = context.read<AuthProvider>();

    // Cargar lista de empresas desde la API
    await authProvider.cargarEmpresas();

    // Preseleccionar la empresa de la última sesión, o la única disponible
    final empresaRecordada = await authProvider.getEmpresaRecordada();
    if (mounted) {
      setState(() {
        final empresas = authProvider.empresas;
        if (empresaRecordada != null &&
            empresas.any((e) => e['codigo'] == empresaRecordada)) {
          _empresaSeleccionada = empresaRecordada;
        } else if (empresas.length == 1) {
          _empresaSeleccionada = empresas.first['codigo'] as String?;
        }
        // Si no hay lista (sin conexión), precargar el código en el campo manual
        if (empresas.isEmpty && empresaRecordada != null) {
          _empresaManualController.text = empresaRecordada;
        }
      });
    }

    final cedula = await authProvider.getCedulaRecordada();
    if (cedula != null && cedula.isNotEmpty && mounted) {
      _cedulaController.text = cedula;
      setState(() => _recordarUsuario = true);
    }
  }

  Future<void> _verificarConexion() async {
    final result = await Connectivity().checkConnectivity();
    if (mounted) {
      setState(() {
        _isConnected = !result.contains(ConnectivityResult.none);
      });
    }

    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((result) {
      if (mounted) {
        setState(() {
          _isConnected = !result.contains(ConnectivityResult.none);
        });
      }
    });

    _probarServidor();
  }

  /// Prueba real contra la API (GET /api/test, sin base de datos).
  /// Se ejecuta al abrir y al tocar el indicador de conexión.
  Future<void> _probarServidor() async {
    if (!mounted) return;
    setState(() => _servidorOk = null);
    final ok = await ApiClient().testConnection();
    if (mounted) {
      setState(() => _servidorOk = ok);
      // Si el servidor volvió y no tenemos empresas, reintentar cargarlas
      if (ok && context.read<AuthProvider>().empresas.isEmpty) {
        await context.read<AuthProvider>().cargarEmpresas();
        if (mounted) setState(() {});
      }
    }
  }

  String get _empresaParaLogin {
    if (_empresaSeleccionada != null) return _empresaSeleccionada!;
    return _empresaManualController.text.trim();
  }

  Future<void> _login() async {
    final authProvider = context.read<AuthProvider>();

    final empresa = _empresaParaLogin;
    final cedula = _cedulaController.text.trim();
    final password = _passwordController.text.trim();

    if (empresa.isEmpty) {
      _mostrarError('Selecciona tu empresa');
      return;
    }
    if (cedula.isEmpty) {
      _mostrarError('Ingresa tu cédula o código');
      return;
    }
    if (password.isEmpty) {
      _mostrarError('Ingresa tu contraseña');
      return;
    }

    final exitoso = await authProvider.login(empresa, cedula, password);

    if (exitoso && mounted) {
      if (_recordarUsuario) {
        await authProvider.guardarCedulaRecordada(cedula);
      } else {
        await authProvider.limpiarCedulaRecordada();
      }
    } else if (!exitoso && mounted && authProvider.error != null) {
      _mostrarError(authProvider.error!);
    }
  }

  void _mostrarError(String mensaje) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: AppTheme.error, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(mensaje)),
          ],
        ),
        backgroundColor: AppTheme.surface,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _cedulaController.dispose();
    _passwordController.dispose();
    _empresaManualController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Consumer<AuthProvider>(
          builder: (context, authProvider, _) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  const SizedBox(height: 48),
                  _buildLogo(),
                  const SizedBox(height: 40),
                  _buildLabel('EMPRESA'),
                  const SizedBox(height: 8),
                  _buildEmpresaField(authProvider),
                  const SizedBox(height: 24),
                  _buildLabel('USUARIO'),
                  const SizedBox(height: 8),
                  _buildCedulaField(),
                  const SizedBox(height: 24),
                  _buildLabel('CONTRASEÑA'),
                  const SizedBox(height: 8),
                  _buildPasswordField(),
                  const SizedBox(height: 20),
                  _buildRecordarme(),
                  const SizedBox(height: 32),
                  _buildLoginButton(authProvider.estaCargando),
                  const SizedBox(height: 48),
                  _buildConnectionStatus(),
                  const SizedBox(height: 12),
                  _buildVersion(),
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // === LOGO ===
  Widget _buildLogo() {
    return Column(
      children: [
        // Logo GyfSoftware Movil
        // Alternativa sin tarjeta blanca: 'assets/images/logo_login_dark.png'
        Image.asset(
          'assets/images/logo_login_card.png',
          width: 280,
          fit: BoxFit.contain,
        ),
        const SizedBox(height: 12),
        const Text(
          'Pedidos para vendedores',
          style: TextStyle(
            fontSize: 14,
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }

  // === LABEL ===
  Widget _buildLabel(String text) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppTheme.textSecondary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  // === CAMPO EMPRESA ===
  Widget _buildEmpresaField(AuthProvider authProvider) {
    if (authProvider.cargandoEmpresas) {
      return Container(
        height: 56,
        decoration: BoxDecoration(
          color: AppTheme.surfaceLight,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    final empresas = authProvider.empresas;

    // Sin conexión o lista vacía: campo manual para escribir el código
    if (empresas.isEmpty) {
      return TextField(
        controller: _empresaManualController,
        keyboardType: TextInputType.number,
        style: const TextStyle(color: AppTheme.textPrimary),
        decoration: InputDecoration(
          hintText: 'Código de empresa (Ej: 001)',
          prefixIcon:
              const Icon(Icons.business_outlined, color: AppTheme.textSecondary),
          filled: true,
          fillColor: AppTheme.surfaceLight,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      );
    }

    // Con lista de empresas: selector desplegable
    return DropdownButtonFormField<String>(
      value: _empresaSeleccionada,
      hint: const Text(
        'Selecciona tu empresa',
        style: TextStyle(color: AppTheme.textSecondary),
      ),
      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16),
      dropdownColor: AppTheme.surface,
      decoration: InputDecoration(
        prefixIcon:
            const Icon(Icons.business_outlined, color: AppTheme.textSecondary),
        filled: true,
        fillColor: AppTheme.surfaceLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      items: empresas.map((e) {
        return DropdownMenuItem<String>(
          value: e['codigo'] as String,
          child: Text(e['nombre'] as String? ?? e['codigo'] as String),
        );
      }).toList(),
      onChanged: (value) => setState(() => _empresaSeleccionada = value),
    );
  }

  // === CAMPO CÉDULA ===
  Widget _buildCedulaField() {
    return TextField(
      controller: _cedulaController,
      keyboardType: TextInputType.text,
      style: const TextStyle(color: AppTheme.textPrimary),
      decoration: InputDecoration(
        hintText: 'Ej: 01',
        prefixIcon:
            const Icon(Icons.person_outline, color: AppTheme.textSecondary),
        filled: true,
        fillColor: AppTheme.surfaceLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  // === CAMPO PASSWORD ===
  Widget _buildPasswordField() {
    return TextField(
      controller: _passwordController,
      obscureText: _ocultarPassword,
      style: const TextStyle(color: AppTheme.textPrimary),
      onSubmitted: (_) => _login(),
      decoration: InputDecoration(
        hintText: '••••••••',
        prefixIcon:
            const Icon(Icons.lock_outline, color: AppTheme.textSecondary),
        suffixIcon: IconButton(
          icon: Icon(
            _ocultarPassword
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            color: AppTheme.textSecondary,
          ),
          onPressed: () =>
              setState(() => _ocultarPassword = !_ocultarPassword),
        ),
        filled: true,
        fillColor: AppTheme.surfaceLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  // === RECORDARME ===
  Widget _buildRecordarme() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'Recordarme',
          style: TextStyle(color: AppTheme.textPrimary, fontSize: 14),
        ),
        Switch(
          value: _recordarUsuario,
          onChanged: (value) => setState(() => _recordarUsuario = value),
          activeColor: AppTheme.primary,
          activeTrackColor: AppTheme.primary.withOpacity(0.4),
          inactiveThumbColor: AppTheme.textSecondary,
          inactiveTrackColor: AppTheme.surfaceLight,
        ),
      ],
    );
  }

  // === BOTÓN LOGIN ===
  Widget _buildLoginButton(bool estaCargando) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: estaCargando ? null : _login,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.buttonAccent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppTheme.buttonAccent.withOpacity(0.5),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
        child: estaCargando
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2.5),
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'INICIAR SESIÓN',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1),
                  ),
                  SizedBox(width: 8),
                  Icon(Icons.login_rounded, size: 20),
                ],
              ),
      ),
    );
  }

  // === INDICADOR DE CONEXIÓN (tocable: prueba el servidor) ===
  Widget _buildConnectionStatus() {
    final Color color;
    final String texto;
    final Widget icono;

    if (!_isConnected) {
      color = AppTheme.error;
      texto = 'SIN CONEXIÓN A INTERNET';
      icono = _dot(color);
    } else if (_servidorOk == null) {
      color = AppTheme.textSecondary;
      texto = 'PROBANDO SERVIDOR...';
      icono = const SizedBox(
        width: 8,
        height: 8,
        child: CircularProgressIndicator(strokeWidth: 1.5),
      );
    } else if (_servidorOk == true) {
      color = AppTheme.accent;
      texto = 'SERVIDOR EN LÍNEA';
      icono = _dot(color);
    } else {
      color = AppTheme.error;
      texto = 'SERVIDOR NO DISPONIBLE';
      icono = _dot(color);
    }

    return InkWell(
      onTap: _probarServidor,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            icono,
            const SizedBox(width: 8),
            Text(
              texto,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.refresh_rounded, size: 14, color: color),
          ],
        ),
      ),
    );
  }

  Widget _dot(Color color) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }

  // === VERSIÓN ===
  Widget _buildVersion() {
    return Column(
      children: [
        Text(
          ApiConstants.appName.toUpperCase(),
          style: const TextStyle(
              fontSize: 11, color: AppTheme.textSecondary, letterSpacing: 1),
        ),
        const SizedBox(height: 2),
        Text(
          'v${ApiConstants.appVersion}',
          style: TextStyle(
              fontSize: 11, color: AppTheme.textSecondary.withOpacity(0.6)),
        ),
      ],
    );
  }
}