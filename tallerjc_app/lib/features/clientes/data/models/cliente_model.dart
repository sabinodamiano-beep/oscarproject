import '../../domain/entities/cliente.dart';

class ClienteModel extends Cliente {
  const ClienteModel({
    required super.uidCliente,
    required super.codigo,
    required super.cedula,
    required super.tipoCedula,
    required super.nombres,
    required super.apellidos,
    required super.telefonoCelular,
    required super.telefonoCasa,
    required super.telefonoOficina,
    required super.direccion,
    required super.email,
    required super.comentario,
    required super.status,
    super.fechaIngreso,
  });

  /// Desde JSON del endpoint GET /api/clientes
  factory ClienteModel.fromJson(Map<String, dynamic> json) {
    return ClienteModel(
      uidCliente: json['uid_cliente'] ?? 0,
      codigo: json['str_cliente_codigo']?.toString().trim() ?? '',
      cedula: json['str_cliente_cedula']?.toString().trim() ?? '',
      tipoCedula: json['str_cliente_tipo_cedula']?.toString().trim() ?? 'V',
      nombres: json['str_cliente_nombres']?.toString().trim() ?? '',
      apellidos: json['str_cliente_apellidos']?.toString().trim() ?? '',
      telefonoCelular: json['str_cliente_telefono_celular']?.toString().trim() ?? '',
      telefonoCasa: json['str_cliente_telefono_casa']?.toString().trim() ?? '',
      telefonoOficina: json['str_cliente_telefono_oficina']?.toString().trim() ?? '',
      direccion: json['str_cliente_direccion']?.toString().trim() ?? '',
      email: json['str_cliente_email']?.toString().trim() ?? '',
      comentario: json['str_cliente_comentario']?.toString().trim() ?? '',
      status: json['str_cliente_status']?.toString().trim() ?? '',
      fechaIngreso: json['dte_cliente_ingreso'] != null
          ? DateTime.tryParse(json['dte_cliente_ingreso'].toString())
          : null,
    );
  }

  /// Para enviar al endpoint POST /api/clientes
  static Map<String, dynamic> toCreateJson({
    required String tipoCedula,
    required String cedula,
    required String nombres,
    required String apellidos,
    required String telefonoCelular,
    String? telefonoCasa,
    String? telefonoOficina,
    String? direccion,
    String? email,
    String? comentario,
  }) {
    return {
      'tipo_cedula': tipoCedula,
      'cedula': cedula,
      'nombres': nombres,
      'apellidos': apellidos,
      'telefono_celular': telefonoCelular,
      if (telefonoCasa != null && telefonoCasa.isNotEmpty)
        'telefono_casa': telefonoCasa,
      if (telefonoOficina != null && telefonoOficina.isNotEmpty)
        'telefono_oficina': telefonoOficina,
      if (direccion != null && direccion.isNotEmpty)
        'direccion': direccion,
      if (email != null && email.isNotEmpty)
        'email': email,
      if (comentario != null && comentario.isNotEmpty)
        'comentario': comentario,
    };
  }
}