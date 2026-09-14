import '../entities/cliente.dart';

abstract class ClientesRepository {
  /// Listar clientes, opcionalmente filtrados por búsqueda
  Future<List<Cliente>> getClientes({String? buscar});

  /// Obtener detalle de un cliente por su uid
  Future<Cliente> getClienteDetalle(int uidCliente);

  /// Crear un cliente nuevo, retorna uid y código generados
  Future<Map<String, dynamic>> crearCliente({
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
  });
}