import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Base de datos local (SQLite). UN ARCHIVO POR EMPRESA: `licores_<codEmpresa>.db`.
///
/// Diseño: cada fila de catálogo se guarda tal como la devuelve la API
/// (columna `json`) más columnas de búsqueda ya normalizadas. Así los
/// modelos existentes (`ClienteModel.fromJson`, `ItemModel.fromJson`) se
/// reutilizan sin mapeos adicionales y cualquier columna nueva de la API
/// llega al caché sin tocar este archivo.
class LocalDatabase {
  LocalDatabase._();
  static final LocalDatabase instance = LocalDatabase._();

  static const int _version = 2;

  Database? _db;
  String? _empresa;

  /// Empresa cuya base está abierta (null si ninguna).
  String? get empresa => _empresa;
  bool get abierta => _db != null;

  Database get db {
    final d = _db;
    if (d == null) throw StateError('Base local no abierta (falta abrir(codEmpresa))');
    return d;
  }

  /// Abre (o crea) la base de la empresa indicada. Si ya está abierta otra
  /// empresa, la cierra primero: nunca hay dos tenants mezclados en memoria.
  Future<Database> abrir(String codEmpresa) async {
    if (_db != null && _empresa == codEmpresa) return _db!;
    await cerrar();
    final ruta = p.join(await getDatabasesPath(), 'licores_$codEmpresa.db');
    _db = await openDatabase(ruta,
        version: _version, onCreate: _crearEsquema, onUpgrade: _migrar);
    _empresa = codEmpresa;
    return _db!;
  }

  Future<void> cerrar() async {
    await _db?.close();
    _db = null;
    _empresa = null;
  }

  Future<void> _crearEsquema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE clientes (
        uid_cliente INTEGER PRIMARY KEY,
        busqueda    TEXT NOT NULL,
        json        TEXT NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE items (
        coditems  TEXT PRIMARY KEY,
        desitems  TEXT NOT NULL DEFAULT '',
        linea     TEXT NOT NULL DEFAULT '',
        busqueda  TEXT NOT NULL,
        json      TEXT NOT NULL
      )''');
    await db.execute('CREATE INDEX idx_items_linea ON items(linea)');

    // Outbox de pedidos (se usa en la Sesión 2; el esquema se crea desde ya
    // para no necesitar migración).
    await db.execute('''
      CREATE TABLE pedidos_outbox (
        uuid           TEXT PRIMARY KEY,
        uid_vendedor   TEXT NOT NULL,
        uid_cliente    INTEGER NOT NULL,
        cliente_nombre TEXT NOT NULL DEFAULT '',
        observaciones  TEXT NOT NULL DEFAULT '',
        items_json     TEXT NOT NULL,
        total_local    REAL NOT NULL DEFAULT 0,
        total_items    INTEGER NOT NULL DEFAULT 0,
        estado         TEXT NOT NULL DEFAULT 'pendiente',
        intentos       INTEGER NOT NULL DEFAULT 0,
        ultimo_error   TEXT,
        uid_pedido     TEXT,
        fecreg         TEXT NOT NULL,
        fecmod         TEXT NOT NULL
      )''');
    await db.execute('CREATE INDEX idx_outbox_vend_estado ON pedidos_outbox(uid_vendedor, estado)');

    await db.execute('CREATE TABLE meta (clave TEXT PRIMARY KEY, valor TEXT)');

    await _crearEsquemaCobros(db);
  }

  /// v2 (cobranza offline): caché de CxC del vendedor + cola de cobros.
  Future<void> _migrar(Database db, int desde, int hasta) async {
    if (desde < 2) await _crearEsquemaCobros(db);
  }

  Future<void> _crearEsquemaCobros(Database db) async {
    // Última foto de las cuentas por cobrar de los clientes del vendedor
    // (GET /cobros/cxc-vendedor). Cada fila guarda el JSON tal como lo
    // devuelve la API, igual que clientes/items.
    await db.execute('''
      CREATE TABLE cxc_cache (
        uid_cliente INTEGER NOT NULL,
        tipodoc     TEXT NOT NULL,
        iddoc       TEXT NOT NULL,
        saldo       REAL NOT NULL DEFAULT 0,
        json        TEXT NOT NULL,
        PRIMARY KEY (uid_cliente, tipodoc, iddoc)
      )''');
    await db.execute('CREATE INDEX idx_cxc_cliente ON cxc_cache(uid_cliente)');

    // Cola de cobros registrados sin señal. payload_json es el body exacto
    // de POST /cobros (con client_uuid = uuid); resumen_json guarda lo que
    // hace falta para pintar la tarjeta y el recibo sin volver a la red.
    await db.execute('''
      CREATE TABLE cobros_outbox (
        uuid           TEXT PRIMARY KEY,
        uid_vendedor   TEXT NOT NULL,
        uid_cliente    INTEGER NOT NULL,
        cliente_nombre TEXT NOT NULL DEFAULT '',
        payload_json   TEXT NOT NULL,
        resumen_json   TEXT NOT NULL,
        total          REAL NOT NULL DEFAULT 0,
        estado         TEXT NOT NULL DEFAULT 'pendiente',
        intentos       INTEGER NOT NULL DEFAULT 0,
        ultimo_error   TEXT,
        numpago        TEXT,
        fecreg         TEXT NOT NULL,
        fecmod         TEXT NOT NULL
      )''');
    await db.execute(
        'CREATE INDEX idx_cobros_outbox_vend ON cobros_outbox(uid_vendedor, estado)');
  }

  // ---------------------------------------------------------------- meta

  Future<String?> getMeta(String clave) async {
    final r = await db.query('meta', where: 'clave = ?', whereArgs: [clave], limit: 1);
    return r.isEmpty ? null : r.first['valor'] as String?;
  }

  Future<void> setMeta(String clave, String? valor) async {
    await db.insert('meta', {'clave': clave, 'valor': valor},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ------------------------------------------------------------ clientes

  /// Reemplaza el catálogo completo en una sola transacción.
  Future<int> reemplazarClientes(List<dynamic> filas) async {
    return db.transaction((txn) async {
      await txn.delete('clientes');
      final batch = txn.batch();
      for (final f in filas) {
        final m = Map<String, dynamic>.from(f as Map);
        batch.insert('clientes', {
          'uid_cliente': m['uid_cliente'],
          'busqueda': normalizar([
            m['str_cliente_nombres'],
            m['str_cliente_apellidos'],
            m['str_cliente_cedula'],
            m['str_cliente_codigo'],
          ]),
          'json': jsonEncode(m),
        });
      }
      await batch.commit(noResult: true);
      return filas.length;
    });
  }

  /// Mismo criterio que la API: LIKE sobre nombres, apellidos, cédula y
  /// código; más recientes primero.
  Future<List<Map<String, dynamic>>> buscarClientes({String? buscar}) async {
    final term = normalizar([buscar]);
    final rows = await db.query(
      'clientes',
      columns: ['json'],
      where: term.isEmpty ? null : 'busqueda LIKE ?',
      whereArgs: term.isEmpty ? null : ['%$term%'],
      orderBy: 'uid_cliente DESC',
    );
    return rows.map(_decodificar).toList();
  }

  Future<Map<String, dynamic>?> getCliente(int uidCliente) async {
    final rows = await db.query('clientes',
        columns: ['json'], where: 'uid_cliente = ?', whereArgs: [uidCliente], limit: 1);
    return rows.isEmpty ? null : _decodificar(rows.first);
  }

  Future<int> contarClientes() async =>
      Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM clientes')) ?? 0;

  // --------------------------------------------------------------- items

  Future<int> reemplazarItems(List<dynamic> filas) async {
    return db.transaction((txn) async {
      await txn.delete('items');
      final batch = txn.batch();
      for (final f in filas) {
        final m = Map<String, dynamic>.from(f as Map);
        batch.insert('items', {
          'coditems': (m['coditems'] ?? '').toString().trim(),
          'desitems': (m['desitems'] ?? '').toString().trim(),
          'linea': (m['Nombre_Linea'] ?? '').toString().trim(),
          'busqueda': normalizar([m['desitems'], m['coditems'], m['CodBarra']]),
          'json': jsonEncode(m),
        });
      }
      await batch.commit(noResult: true);
      return filas.length;
    });
  }

  /// Mismo criterio que la API: solo activos (el sync ya baja solo activos),
  /// LIKE sobre descripción/código/barra, filtro por nombre de línea,
  /// orden alfabético.
  Future<List<Map<String, dynamic>>> buscarItems({String? buscar, String? linea}) async {
    final where = <String>[];
    final args = <Object>[];
    final term = normalizar([buscar]);
    if (term.isNotEmpty) {
      where.add('busqueda LIKE ?');
      args.add('%$term%');
    }
    if (linea != null && linea.trim().isNotEmpty) {
      where.add('linea = ?');
      args.add(linea.trim());
    }
    final rows = await db.query(
      'items',
      columns: ['json'],
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: where.isEmpty ? null : args,
      orderBy: 'desitems COLLATE NOCASE',
    );
    return rows.map(_decodificar).toList();
  }

  Future<Map<String, dynamic>?> getItem(String coditems) async {
    final rows = await db.query('items',
        columns: ['json'], where: 'coditems = ?', whereArgs: [coditems.trim()], limit: 1);
    return rows.isEmpty ? null : _decodificar(rows.first);
  }

  /// Líneas distintas presentes en el caché (equivale a GET /lineas).
  Future<List<String>> lineasLocales() async {
    final rows = await db.rawQuery(
        "SELECT DISTINCT linea FROM items WHERE linea <> '' ORDER BY linea COLLATE NOCASE");
    return rows.map((r) => r['linea'] as String).toList();
  }

  Future<int> contarItems() async =>
      Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM items')) ?? 0;

  // -------------------------------------------------------------- outbox
  // (Las filas se serializan/deserializan en PedidoLocal.toRow / fromRow)

  Future<void> insertarOutbox(Map<String, Object?> fila) async {
    await db.insert('pedidos_outbox', fila, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> actualizarOutbox(String uuid, Map<String, Object?> campos) async {
    await db.update('pedidos_outbox', campos, where: 'uuid = ?', whereArgs: [uuid]);
  }

  Future<void> eliminarOutbox(String uuid) async {
    await db.delete('pedidos_outbox', where: 'uuid = ?', whereArgs: [uuid]);
  }

  Future<Map<String, Object?>?> getOutbox(String uuid) async {
    final r = await db.query('pedidos_outbox', where: 'uuid = ?', whereArgs: [uuid], limit: 1);
    return r.isEmpty ? null : r.first;
  }

  /// Pedidos locales del vendedor, FIFO (más antiguo primero) para el envío,
  /// o más reciente primero para mostrar.
  Future<List<Map<String, Object?>>> listarOutbox(
    String uidVendedor, {
    List<String>? estados,
    bool fifo = false,
  }) async {
    final where = StringBuffer('uid_vendedor = ?');
    final args = <Object>[uidVendedor];
    if (estados != null && estados.isNotEmpty) {
      where.write(' AND estado IN (${List.filled(estados.length, '?').join(',')})');
      args.addAll(estados);
    }
    return db.query('pedidos_outbox',
        where: where.toString(), whereArgs: args, orderBy: fifo ? 'fecreg ASC' : 'fecreg DESC');
  }

  Future<int> contarOutbox(String uidVendedor, List<String> estados) async {
    final r = await db.rawQuery(
      'SELECT COUNT(*) FROM pedidos_outbox WHERE uid_vendedor = ? AND estado IN (${List.filled(estados.length, '?').join(',')})',
      [uidVendedor, ...estados],
    );
    return Sqflite.firstIntValue(r) ?? 0;
  }

  /// Limpia los pedidos ya enviados con más de [dias] días (ya viven en el servidor).
  Future<int> purgarEnviados({int dias = 3}) async {
    final limite = DateTime.now().subtract(Duration(days: dias)).toIso8601String();
    return db.delete('pedidos_outbox', where: "estado = 'enviado' AND fecmod < ?", whereArgs: [limite]);
  }

  // ----------------------------------------------------------- cxc cache

  /// Reemplaza la foto completa de CxC del vendedor (una transacción).
  Future<int> reemplazarCxc(List<dynamic> filas) async {
    return db.transaction((txn) async {
      await txn.delete('cxc_cache');
      final batch = txn.batch();
      for (final f in filas) {
        final m = Map<String, dynamic>.from(f as Map);
        batch.insert('cxc_cache', {
          'uid_cliente': (m['uid_cliente'] as num?)?.toInt() ?? 0,
          'tipodoc': (m['tipodoc'] ?? '').toString().trim(),
          'iddoc': (m['iddoc'] ?? '').toString().trim(),
          'saldo': double.tryParse('${m['SaldoActual'] ?? 0}') ?? 0,
          'json': jsonEncode(m),
        });
      }
      await batch.commit(noResult: true);
      return filas.length;
    });
  }

  /// Documentos pendientes de un cliente según la última sincronización.
  Future<List<Map<String, dynamic>>> cxcCliente(int uidCliente) async {
    final rows = await db.query('cxc_cache',
        columns: ['json'],
        where: 'uid_cliente = ?',
        whereArgs: [uidCliente],
        orderBy: 'iddoc ASC');
    return rows.map(_decodificar).toList();
  }

  Future<int> contarCxc() async =>
      Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM cxc_cache')) ?? 0;

  // ------------------------------------------------------- cobros outbox
  // (Las filas se serializan/deserializan en CobroLocal.toRow / fromRow)

  Future<void> insertarCobroOutbox(Map<String, Object?> fila) async {
    await db.insert('cobros_outbox', fila, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> actualizarCobroOutbox(String uuid, Map<String, Object?> campos) async {
    await db.update('cobros_outbox', campos, where: 'uuid = ?', whereArgs: [uuid]);
  }

  Future<void> eliminarCobroOutbox(String uuid) async {
    await db.delete('cobros_outbox', where: 'uuid = ?', whereArgs: [uuid]);
  }

  Future<Map<String, Object?>?> getCobroOutbox(String uuid) async {
    final r = await db.query('cobros_outbox', where: 'uuid = ?', whereArgs: [uuid], limit: 1);
    return r.isEmpty ? null : r.first;
  }

  Future<List<Map<String, Object?>>> listarCobrosOutbox(
    String uidVendedor, {
    List<String>? estados,
    bool fifo = false,
  }) async {
    final where = StringBuffer('uid_vendedor = ?');
    final args = <Object>[uidVendedor];
    if (estados != null && estados.isNotEmpty) {
      where.write(' AND estado IN (${List.filled(estados.length, '?').join(',')})');
      args.addAll(estados);
    }
    return db.query('cobros_outbox',
        where: where.toString(), whereArgs: args, orderBy: fifo ? 'fecreg ASC' : 'fecreg DESC');
  }

  Future<int> contarCobrosOutbox(String uidVendedor, List<String> estados) async {
    final r = await db.rawQuery(
      'SELECT COUNT(*) FROM cobros_outbox WHERE uid_vendedor = ? AND estado IN (${List.filled(estados.length, '?').join(',')})',
      [uidVendedor, ...estados],
    );
    return Sqflite.firstIntValue(r) ?? 0;
  }

  /// Limpia los cobros ya enviados con más de [dias] días (viven en el servidor).
  /// Los rechazados NO se purgan: los resuelve el vendedor a mano.
  Future<int> purgarCobrosEnviados({int dias = 3}) async {
    final limite = DateTime.now().subtract(Duration(days: dias)).toIso8601String();
    return db.delete('cobros_outbox',
        where: "estado = 'enviado' AND fecmod < ?", whereArgs: [limite]);
  }

  // ------------------------------------------------------------ helpers

  Map<String, dynamic> _decodificar(Map<String, Object?> row) =>
      Map<String, dynamic>.from(jsonDecode(row['json'] as String) as Map);

  /// Minúsculas, sin acentos, espacios colapsados. Se aplica igual al texto
  /// guardado y al término buscado, así "Jose" encuentra "JOSÉ".
  static String normalizar(List<dynamic> partes) {
    final s = partes.where((x) => x != null).map((x) => x.toString()).join(' ').toLowerCase();
    const con = 'áàäâãéèëêíìïîóòöôõúùüûñç';
    const sin = 'aaaaaeeeeiiiiooooouuuunc';
    final sb = StringBuffer();
    for (final ch in s.runes) {
      final c = String.fromCharCode(ch);
      final i = con.indexOf(c);
      sb.write(i >= 0 ? sin[i] : c);
    }
    return sb.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
