/// Entidad de producto (licores, bebidas, etc.)
class Item {
  final String coditems;
  final String desitems;
  final double existencia;
  final String ubicacion;
  final String codBarra;
  final String activo;
  final String status;
  final double precioPvp;
  final double precioEspecial;
  final double precioDistribuidor;
  final double precioMayor;
  final double precioOferta;
  final String ventaCaja;
  final String ventaBotella;
  final double litros;
  final int codMarca;
  final int codLinea;
  final int codPresentacion;
  final String nombreMarca;
  final double dolPre;          // precio por caja/unidad en USD (PVP)
  final double dolOfe;          // precio Oferta
  final double dolMay;          // precio Mayor
  final double dolDis;          // precio Distribuidor
  final double dolEsp;          // precio Especial
  final double cantunidad;      // unidades (botellas) por caja
  final String nombreLinea;
  final String nombrePresentacion;

  const Item({
    required this.coditems,
    required this.desitems,
    required this.existencia,
    required this.ubicacion,
    required this.codBarra,
    required this.activo,
    required this.status,
    required this.precioPvp,
    required this.precioEspecial,
    required this.precioDistribuidor,
    required this.precioMayor,
    required this.precioOferta,
    required this.ventaCaja,
    required this.ventaBotella,
    required this.litros,
    required this.codMarca,
    required this.codLinea,
    required this.codPresentacion,
    required this.nombreMarca,
    this.dolPre = 0,
    this.dolOfe = 0,
    this.dolMay = 0,
    this.dolDis = 0,
    this.dolEsp = 0,
    this.cantunidad = 1,
    this.nombreLinea = '',
    this.nombrePresentacion = '',
  });

  bool get tieneStock => existencia > 0;

  // ------------------------------------------------------- niveles de precio

  /// Etiqueta legible de cada nivel. Las claves son las que entiende el API.
  static const Map<String, String> nombresNivel = {
    'pvp': 'PVP',
    'ofe': 'Oferta',
    'may': 'Mayor',
    'dis': 'Distribuidor',
    'esp': 'Especial',
  };

  /// Precio de un nivel (0 si ese nivel no está cargado en InvenSoft).
  double precioDe(String nivel) {
    switch (nivel) {
      case 'ofe':
        return dolOfe;
      case 'may':
        return dolMay;
      case 'dis':
        return dolDis;
      case 'esp':
        return dolEsp;
      case 'pvp':
      default:
        return dolPre;
    }
  }

  /// Solo los niveles con precio cargado (> 0), en orden fijo.
  /// Si Sabino no ha cargado Oferta/Mayor/etc., aquí solo aparece el PVP.
  Map<String, double> get preciosDisponibles {
    final r = <String, double>{};
    for (final n in nombresNivel.keys) {
      final p = precioDe(n);
      if (p > 0) r[n] = p;
    }
    return r;
  }

  bool get tieneVariosPrecios => preciosDisponibles.length > 1;

  bool get tieneCodBarra => codBarra.isNotEmpty;
  bool get vendeEnCaja => ventaCaja == '1';
  bool get vendeEnBotella => ventaBotella == '1';

  /// Solo tiene sentido pedir botellas sueltas si la caja trae más de una
  bool get permiteBotellas => vendeEnBotella && cantunidad > 1;
  double get precioBotella => cantunidad > 0 ? dolPre / cantunidad : dolPre;
}