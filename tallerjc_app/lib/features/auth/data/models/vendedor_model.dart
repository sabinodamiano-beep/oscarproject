import '../../domain/entities/vendedor.dart';

/// Modelo de vendedor - capa de datos
/// Extiende la entidad y agrega serialización JSON
class VendedorModel extends Vendedor {
  const VendedorModel({
    required super.uidVendedor,
    required super.nombre,
    required super.apellido,
    required super.cedula,
    super.correo,
    super.letra,
    super.comision,
  });

  /// Desde JSON del endpoint POST /api/login
  factory VendedorModel.fromJson(Map<String, dynamic> json) {
    return VendedorModel(
      uidVendedor: json['uid_vendedor']?.toString() ?? '',
      nombre: json['nombre']?.toString().trim() ?? '',
      apellido: json['apellido']?.toString().trim() ?? '',
      cedula: json['cedula']?.toString() ?? '',
      correo: json['correo']?.toString().trim() ?? '',
      letra: json['letra']?.toString().trim() ?? '',
      comision: (json['comision'] ?? 0).toDouble(),
    );
  }

  /// Para guardar en SharedPreferences
  Map<String, dynamic> toJson() {
    return {
      'uid_vendedor': uidVendedor,
      'nombre': nombre,
      'apellido': apellido,
      'cedula': cedula,
      'correo': correo,
      'letra': letra,
      'comision': comision,
    };
  }

  /// Desde SharedPreferences
  factory VendedorModel.fromStorage(Map<String, dynamic> json) {
    return VendedorModel(
      uidVendedor: json['uid_vendedor'] ?? '',
      nombre: json['nombre'] ?? '',
      apellido: json['apellido'] ?? '',
      cedula: json['cedula'] ?? '',
      correo: json['correo'] ?? '',
      letra: json['letra'] ?? '',
      comision: (json['comision'] ?? 0).toDouble(),
    );
  }
}