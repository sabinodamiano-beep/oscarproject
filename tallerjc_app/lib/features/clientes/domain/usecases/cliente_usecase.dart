import 'package:gyfsoftware_movil/features/clientes/domain/repositories/cliente_repository.dart';

import '../entities/cliente.dart';


/// Obtener lista de clientes
class GetClientesUseCase {
  final ClientesRepository _repository;

  GetClientesUseCase({required ClientesRepository repository})
      : _repository = repository;

  Future<List<Cliente>> execute({String? buscar}) async {
    return await _repository.getClientes(buscar: buscar);
  }
}

/// Obtener detalle de un cliente
class GetClienteDetalleUseCase {
  final ClientesRepository _repository;

  GetClienteDetalleUseCase({required ClientesRepository repository})
      : _repository = repository;

  Future<Cliente> execute(int uidCliente) async {
    return await _repository.getClienteDetalle(uidCliente);
  }
}

/// Crear un cliente nuevo
class CrearClienteUseCase {
  final ClientesRepository _repository;

  CrearClienteUseCase({required ClientesRepository repository})
      : _repository = repository;

  Future<Map<String, dynamic>> execute({
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
  }) async {
    // Validaciones de negocio
    if (cedula.trim().isEmpty) {
      throw ArgumentError('La cédula es obligatoria');
    }
    if (nombres.trim().isEmpty) {
      throw ArgumentError('El nombre es obligatorio');
    }
    if (telefonoCelular.trim().isEmpty) {
      throw ArgumentError('El teléfono celular es obligatorio');
    }

    return await _repository.crearCliente(
      tipoCedula: tipoCedula,
      cedula: cedula.trim(),
      nombres: nombres.trim(),
      apellidos: apellidos.trim(),
      telefonoCelular: telefonoCelular.trim(),
      telefonoCasa: telefonoCasa?.trim(),
      telefonoOficina: telefonoOficina?.trim(),
      direccion: direccion?.trim(),
      email: email?.trim(),
      comentario: comentario?.trim(),
    );
  }
}