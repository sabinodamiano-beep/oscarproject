import 'package:gyfsoftware_movil/features/items/domain/repositories/item_repository.dart';

import '../entities/item.dart';
import '../entities/marca.dart';

/// Obtener lista de productos
class GetItemsUseCase {
  final ItemsRepository _repository;

  GetItemsUseCase({required ItemsRepository repository})
      : _repository = repository;

  Future<List<Item>> execute({String? buscar, String? linea}) async {
    return await _repository.getItems(buscar: buscar, linea: linea);
  }
}

/// Obtener detalle de un producto
class GetItemDetalleUseCase {
  final ItemsRepository _repository;

  GetItemDetalleUseCase({required ItemsRepository repository})
      : _repository = repository;

  Future<Item> execute(String coditems) async {
    return await _repository.getItemDetalle(coditems);
  }
}

/// Obtener marcas
/// Obtener líneas (categorías) de productos
class GetLineasUseCase {
  final ItemsRepository _repository;

  GetLineasUseCase({required ItemsRepository repository})
      : _repository = repository;

  Future<List<String>> execute() async {
    return await _repository.getLineas();
  }
}

class GetMarcasUseCase {
  final ItemsRepository _repository;

  GetMarcasUseCase({required ItemsRepository repository})
      : _repository = repository;

  Future<List<Marca>> execute() async {
    return await _repository.getMarcas();
  }
}