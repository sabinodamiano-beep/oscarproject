/// Entidad de vendedor - capa de dominio
class Vendedor {
  final String uidVendedor;
  final String nombre;
  final String apellido;
  final String cedula;
  final String correo;
  final String letra;
  final double comision;

  const Vendedor({
    required this.uidVendedor,
    required this.nombre,
    required this.apellido,
    required this.cedula,
    this.correo = '',
    this.letra = '',
    this.comision = 0.0,
  });

  String get nombreCompleto => '$nombre $apellido'.trim();
}