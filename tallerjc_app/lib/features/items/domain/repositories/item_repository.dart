import '../entities/item.dart';
import '../entities/marca.dart';

abstract class ItemsRepository {
  Future<List<Item>> getItems({String? buscar, String? linea});
  Future<List<String>> getLineas();
  Future<Item> getItemDetalle(String coditems);
  Future<List<Marca>> getMarcas();
}