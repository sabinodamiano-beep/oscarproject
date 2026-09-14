import '../../domain/entities/marca.dart';

class MarcaModel extends Marca {
  const MarcaModel({
    required super.codMarca,
    required super.nombreMarca,
  });

  /// Desde JSON del endpoint GET /api/marcas
  factory MarcaModel.fromJson(Map<String, dynamic> json) {
    return MarcaModel(
      codMarca: json['Cod_Marca'] ?? 0,
      nombreMarca: json['Nombre_Marca']?.toString().trim() ?? '',
    );
  }
}