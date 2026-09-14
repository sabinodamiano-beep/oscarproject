import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:gyfsoftware_movil/features/clientes/presentation/providers/cliente_provider.dart';
import '../../../../core/theme/app_theme.dart';


class ClienteCrearScreen extends StatefulWidget {
  const ClienteCrearScreen({super.key});

  @override
  State<ClienteCrearScreen> createState() => _ClienteCrearScreenState();
}

class _ClienteCrearScreenState extends State<ClienteCrearScreen> {
  final _formKey = GlobalKey<FormState>();

  // Controladores
  final _cedulaController = TextEditingController();
  final _nombresController = TextEditingController();
  final _apellidosController = TextEditingController();
  final _telefonoCelularController = TextEditingController();
  final _telefonoCasaController = TextEditingController();
  final _telefonoOficinaController = TextEditingController();
  final _direccionController = TextEditingController();
  final _emailController = TextEditingController();
  final _comentarioController = TextEditingController();

  String _tipoCedula = 'V';
  final List<String> _tiposCedula = ['V', 'E', 'J', 'G'];

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    final provider = context.read<ClientesProvider>();

    final exitoso = await provider.crearCliente(
      tipoCedula: _tipoCedula,
      cedula: _cedulaController.text.trim(),
      nombres: _nombresController.text.trim(),
      apellidos: _apellidosController.text.trim(),
      telefonoCelular: _telefonoCelularController.text.trim(),
      telefonoCasa: _telefonoCasaController.text.trim(),
      telefonoOficina: _telefonoOficinaController.text.trim(),
      direccion: _direccionController.text.trim(),
      email: _emailController.text.trim(),
      comentario: _comentarioController.text.trim(),
    );

    if (exitoso && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle, color: AppTheme.accent, size: 20),
              SizedBox(width: 10),
              Text('Cliente creado exitosamente'),
            ],
          ),
          backgroundColor: AppTheme.surface,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      Navigator.pop(context, true); // true = se creó un cliente
    } else if (!exitoso && mounted && provider.errorCrear != null) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: AppTheme.error, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(provider.errorCrear!)),
            ],
          ),
          backgroundColor: AppTheme.surface,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  @override
  void dispose() {
    _cedulaController.dispose();
    _nombresController.dispose();
    _apellidosController.dispose();
    _telefonoCelularController.dispose();
    _telefonoCasaController.dispose();
    _telefonoOficinaController.dispose();
    _direccionController.dispose();
    _emailController.dispose();
    _comentarioController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        title: const Text('Nuevo Cliente'),
      ),
      body: Consumer<ClientesProvider>(
        builder: (context, provider, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // === SECCIÓN: IDENTIFICACIÓN ===
                  _buildSectionLabel('IDENTIFICACIÓN'),
                  const SizedBox(height: 12),
                  _buildCedulaRow(),
                  const SizedBox(height: 16),

                  // === SECCIÓN: DATOS PERSONALES ===
                  _buildSectionLabel('DATOS PERSONALES'),
                  const SizedBox(height: 12),
                  _buildField(
                    controller: _nombresController,
                    label: 'Nombres',
                    hint: 'Ej: Juan Carlos',
                    icon: Icons.person_outline,
                    required: true,
                    validator: (v) => v == null || v.trim().isEmpty ? 'El nombre es obligatorio' : null,
                  ),
                  const SizedBox(height: 12),
                  _buildField(
                    controller: _apellidosController,
                    label: 'Apellidos',
                    hint: 'Ej: Pérez García',
                    icon: Icons.person_outline,
                    required: true,
                    validator: (v) => v == null || v.trim().isEmpty ? 'El apellido es obligatorio' : null,
                  ),
                  const SizedBox(height: 16),

                  // === SECCIÓN: TELÉFONOS ===
                  _buildSectionLabel('TELÉFONOS'),
                  const SizedBox(height: 12),
                  _buildField(
                    controller: _telefonoCelularController,
                    label: 'Celular',
                    hint: 'Ej: 0412-1234567',
                    icon: Icons.phone_android_rounded,
                    required: true,
                    keyboardType: TextInputType.phone,
                    validator: (v) => v == null || v.trim().isEmpty ? 'El celular es obligatorio' : null,
                  ),
                  const SizedBox(height: 12),
                  _buildField(
                    controller: _telefonoCasaController,
                    label: 'Casa (opcional)',
                    hint: 'Ej: 0212-1234567',
                    icon: Icons.home_rounded,
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 12),
                  _buildField(
                    controller: _telefonoOficinaController,
                    label: 'Oficina (opcional)',
                    hint: 'Ej: 0212-9876543',
                    icon: Icons.business_rounded,
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 16),

                  // === SECCIÓN: INFORMACIÓN ADICIONAL ===
                  _buildSectionLabel('INFORMACIÓN ADICIONAL'),
                  const SizedBox(height: 12),
                  _buildField(
                    controller: _direccionController,
                    label: 'Dirección (opcional)',
                    hint: 'Ej: Av. Principal, Caracas',
                    icon: Icons.location_on_outlined,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  _buildField(
                    controller: _emailController,
                    label: 'Email (opcional)',
                    hint: 'Ej: cliente@email.com',
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) {
                      if (v != null && v.trim().isNotEmpty) {
                        if (!v.contains('@') || !v.contains('.')) {
                          return 'Email no válido';
                        }
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildField(
                    controller: _comentarioController,
                    label: 'Comentario (opcional)',
                    hint: 'Alguna nota sobre el cliente...',
                    icon: Icons.comment_outlined,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 28),

                  // === BOTÓN GUARDAR ===
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: provider.estaCreando ? null : _guardar,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        disabledBackgroundColor: AppTheme.primary.withOpacity(0.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: provider.estaCreando
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.save_rounded, size: 20, color: Colors.white),
                                SizedBox(width: 10),
                                Text(
                                  'Guardar Cliente',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
                                ),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ==================== WIDGETS AUXILIARES ====================

  Widget _buildSectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: AppTheme.textSecondary,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildCedulaRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Selector tipo cédula
        Container(
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _tipoCedula,
              dropdownColor: AppTheme.surfaceLight,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w600),
              items: _tiposCedula.map((tipo) {
                return DropdownMenuItem(value: tipo, child: Text(tipo));
              }).toList(),
              onChanged: (value) {
                if (value != null) setState(() => _tipoCedula = value);
              },
            ),
          ),
        ),
        const SizedBox(width: 10),
        // Campo cédula
        Expanded(
          child: TextFormField(
            controller: _cedulaController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              hintText: 'Número de cédula',
              hintStyle: TextStyle(color: AppTheme.textSecondary.withOpacity(0.6)),
              prefixIcon: const Icon(Icons.badge_outlined, color: AppTheme.textSecondary, size: 20),
              filled: true,
              fillColor: AppTheme.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.error, width: 1.5),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.error, width: 1.5),
              ),
            ),
            validator: (v) => v == null || v.trim().isEmpty ? 'La cédula es obligatoria' : null,
          ),
        ),
      ],
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool required = false,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: const TextStyle(color: AppTheme.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: AppTheme.textSecondary.withOpacity(0.8), fontSize: 14),
        hintText: hint,
        hintStyle: TextStyle(color: AppTheme.textSecondary.withOpacity(0.4), fontSize: 14),
        prefixIcon: Icon(icon, color: AppTheme.textSecondary, size: 20),
        filled: true,
        fillColor: AppTheme.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.error, width: 1.5),
        ),
      ),
      validator: validator,
    );
  }
}