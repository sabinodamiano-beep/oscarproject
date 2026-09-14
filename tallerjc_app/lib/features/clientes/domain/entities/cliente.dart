/// Entidad de cliente del taller
class Cliente {
  final int uidCliente;
  final String codigo;
  final String cedula;
  final String tipoCedula;
  final String nombres;
  final String apellidos;
  final String telefonoCelular;
  final String telefonoCasa;
  final String telefonoOficina;
  final String direccion;
  final String email;
  final String comentario;
  final String status;
  final DateTime? fechaIngreso;

  const Cliente({
    required this.uidCliente,
    required this.codigo,
    required this.cedula,
    required this.tipoCedula,
    required this.nombres,
    required this.apellidos,
    required this.telefonoCelular,
    required this.telefonoCasa,
    required this.telefonoOficina,
    required this.direccion,
    required this.email,
    required this.comentario,
    required this.status,
    this.fechaIngreso,
  });

  String get nombreCompleto => '$nombres $apellidos'.trim();
  String get cedulaCompleta => '$tipoCedula-$cedula';

  /// Verificar si el teléfono es real (no es el placeholder del VB6)
  bool get tieneTelefonoCelular =>
      telefonoCelular.isNotEmpty && !telefonoCelular.contains('____');
  bool get tieneTelefonoCasa =>
      telefonoCasa.isNotEmpty && !telefonoCasa.contains('____');
  bool get tieneTelefonoOficina =>
      telefonoOficina.isNotEmpty && !telefonoOficina.contains('____');
  bool get tieneComentario =>
      comentario.isNotEmpty && comentario != 'SIN COMENTARIOS';
}