const express = require('express');
const { getConnection, sql } = require('../config/database');
const { verificarToken } = require('../middleware/auth');

const router = express.Router();

// Constantes del módulo (valores observados en tbl_mnotaentrega del VB6)
const COD_ALMACEN = 1;
const TIPODOC = '0001';
const SERIE_INICIAL = '9000001';   // serie propia de la app, no toca tbl_correlativos
const STATUS_EN_PROCESO = '00';
const STATUS_ANULADO = '99';
const TIPOPAGO = '02';
const PLAZO = '01';
const CODUNID_CAJAS = 2;
const WORKSTATION = 'APP-MOVIL';

function round2(n) {
    return Math.round(n * 100) / 100;
}

function ipCliente(req) {
    return (req.ip || '').replace('::ffff:', '').slice(0, 15);
}

// Llave de idempotencia generada por la app (UUID v4). null si no viene o no tiene forma de UUID.
const RE_UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
function normalizarUuid(v) {
    if (!v) return null;
    const u = String(v).trim().toLowerCase();
    return RE_UUID.test(u) ? u : null;
}

// Respuesta de un pedido ya registrado con ese UUID (replay). Misma forma que el 201 original.
function respuestaReplay(fila) {
    return {
        mensaje: 'Pedido ya registrado',
        uid_pedido: fila.uid_pedido,
        total: Number(fila.total),
        items: fila.total_items,
        replay: true
    };
}

// Niveles de precio disponibles por producto (columnas DOL* de tbl_items).
// El vendedor envía el nivel, nunca el monto: el precio siempre sale de la BD.
const NIVELES_PRECIO = {
    pvp: { col: 'DOLpre', nombre: 'PVP' },
    ofe: { col: 'DOLofe', nombre: 'Oferta' },
    may: { col: 'DOLmay', nombre: 'Mayor' },
    dis: { col: 'DOLdis', nombre: 'Distribuidor' },
    esp: { col: 'DOLesp', nombre: 'Especial' }
};

// Resuelve el precio unitario según el nivel pedido. Lanza si el nivel no
// existe o si ese producto no tiene precio cargado en ese nivel.
function precioSegunNivel(producto, nivelCrudo, desitems) {
    const nivel = String(nivelCrudo || 'pvp').trim().toLowerCase();
    const def = NIVELES_PRECIO[nivel];
    if (!def) throw { status: 400, error: `Nivel de precio inválido: ${nivelCrudo}` };
    const precio = Number(producto[def.col]) || 0;
    if (precio <= 0) {
        throw { status: 400, error: `${desitems} no tiene precio ${def.nombre} cargado` };
    }
    return precio;
}

/**
 * Valida los items recibidos contra tbl_items y calcula las líneas del pedido.
 * Lanza { status, error } si algo no es válido.
 */
async function calcularLineas(tx, items) {
    if (!Array.isArray(items) || items.length === 0) {
        throw { status: 400, error: 'El pedido debe tener al menos un producto' };
    }

    const codigos = [...new Set(items.map(i => String(i.coditems).trim()))];
    const reqItems = new sql.Request(tx);
    codigos.forEach((c, idx) => reqItems.input(`c${idx}`, sql.NVarChar, c));
    const prodRes = await reqItems.query(`
        SELECT coditems, desitems, DOLpre, DOLofe, DOLmay, DOLdis, DOLesp,
               cantunidad, VentaBotella, activo
        FROM tbl_items
        WHERE coditems IN (${codigos.map((_, idx) => `@c${idx}`).join(',')})`);
    const productos = {};
    prodRes.recordset.forEach(p => { productos[String(p.coditems).trim()] = p; });

    const lineas = [];
    const vistos = new Set();
    for (const it of items) {
        const cod = String(it.coditems).trim();
        if (vistos.has(cod)) throw { status: 400, error: `Producto ${cod} repetido en el pedido` };
        vistos.add(cod);

        const p = productos[cod];
        const cajas = Number(it.cajas) || 0;
        const botellas = Number(it.botellas) || 0;

        if (!p) throw { status: 400, error: `Producto ${cod} no existe` };
        if (p.activo !== '1') throw { status: 400, error: `Producto ${cod} inactivo` };
        if (cajas < 0 || botellas < 0 || (cajas === 0 && botellas === 0)) {
            throw { status: 400, error: `Cantidad inválida en ${cod}` };
        }
        const cantunidad = Number(p.cantunidad) || 1;
        if (botellas > 0 && !p.VentaBotella) {
            throw { status: 400, error: `${p.desitems.trim()} no se vende por botella` };
        }
        if (botellas >= cantunidad) {
            throw { status: 400, error: `${p.desitems.trim()}: botellas debe ser menor que ${cantunidad}` };
        }

        const precunit = precioSegunNivel(p, it.precio_nivel, p.desitems.trim());
        const total = round2((cajas + botellas / cantunidad) * precunit);
        lineas.push({
            coditems: cod,
            descripcion: p.desitems.trim(),
            cantidad: cajas,
            cantidad_unidad: botellas,
            unidad_total: cajas * cantunidad + botellas,
            precunit,
            total
        });
    }
    return lineas;
}

async function insertarDetalle(tx, uid_pedido, lineas, uid_usuario) {
    for (const l of lineas) {
        await new sql.Request(tx)
            .input('codalmacen', sql.Int, COD_ALMACEN)
            .input('uid_pedido', sql.NVarChar, uid_pedido)
            .input('coditems', sql.NVarChar, l.coditems)
            .input('cantidad', sql.Decimal(18, 4), l.cantidad)
            .input('cantidad_unidad', sql.Decimal(18, 4), l.cantidad_unidad)
            .input('precunit', sql.Money, l.precunit)
            .input('subtotal', sql.Money, l.total)
            .input('total', sql.Money, l.total)
            .input('codunid', sql.Int, CODUNID_CAJAS)
            .input('uid_usuario', sql.Int, uid_usuario)
            .input('workstation', sql.NVarChar, WORKSTATION)
            .input('unidad_total', sql.Char(10), String(l.unidad_total))
            .input('descripcion', sql.NVarChar, l.descripcion)
            .query(`
                INSERT INTO tbl_dpedidos (
                    codalmacen, uid_pedido, coditems, cantidad, cantidad_unidad,
                    precunit, pimp, impuesto, subtotal, total, codunid,
                    uid_usuario, workstation, fecreg, fecmod, unidad_total, descripcion
                ) VALUES (
                    @codalmacen, @uid_pedido, @coditems, @cantidad, @cantidad_unidad,
                    @precunit, 0, 0, @subtotal, @total, @codunid,
                    @uid_usuario, @workstation, GETDATE(), GETDATE(), @unidad_total, @descripcion
                )`);
    }
}

// Deja rastro del error en el log de pm2 (pm2 logs licores-api --err).
// Sin esto, un fallo del servidor solo se ve como "Error interno" en el telefono.
function logError(donde, req, error) {
    const emp = (req && req.usuario && req.usuario.empresa) || '?';
    const ven = (req && req.usuario && req.usuario.uid_vendedor) || '?';
    console.error(`[${new Date().toISOString()}] ${donde} empresa=${emp} vendedor=${ven} ` +
        `number=${error && error.number} -> ${error && (error.message || error.error)}`);
    if (error && error.stack) console.error(error.stack);
}

function responderError(res, error, donde, req) {
    if (error && error.status) return res.status(error.status).json({ error: error.error });
    // Error no previsto: dejarlo en el log antes de responder.
    if (donde) logError(donde, req, error);
    return res.status(500).json({ error: error.message || 'Error interno' });
}

// ---------------------------------------------------------------- POST
// body: { uid_cliente, observaciones?, items: [{ coditems, cajas, botellas }] }
// body: { uid_cliente, observaciones?, items: [...], client_uuid? }
//   client_uuid: UUID generado por la app. Si ya fue registrado, se devuelve el pedido
//   existente (200, replay:true) en vez de crear uno nuevo. Sin client_uuid el
//   comportamiento es el de siempre (retrocompatible con la app 1.1.0).
router.post('/pedidos', verificarToken, async (req, res) => {
    const { uid_cliente, observaciones, items } = req.body;
    if (!uid_cliente) return res.status(400).json({ error: 'Cliente obligatorio' });

    const client_uuid = normalizarUuid(req.body.client_uuid);
    const pool = await getConnection(req.empresa);
    const tx = new sql.Transaction(pool);
    const uid_usuario = parseInt(req.vendedor.uid_vendedor);
    const uid_vendedor = String(req.vendedor.uid_vendedor);

    try {
        await tx.begin(sql.ISOLATION_LEVEL.SERIALIZABLE);

        // --- Idempotencia: ¿ya se procesó este UUID? ---
        // UPDLOCK/HOLDLOCK sobre el rango del uuid: dos reintentos simultáneos del mismo
        // pedido se serializan aquí y el segundo ve la fila que insertó el primero.
        if (client_uuid) {
            const previo = await new sql.Request(tx)
                .input('client_uuid', sql.NVarChar(36), client_uuid)
                .query(`SELECT uid_pedido, total, total_items
                        FROM tbl_app_idempotencia WITH (UPDLOCK, HOLDLOCK)
                        WHERE client_uuid = @client_uuid`);
            if (previo.recordset.length > 0) {
                await tx.commit();
                return res.status(200).json(respuestaReplay(previo.recordset[0]));
            }
        }

        const cli = await new sql.Request(tx)
            .input('uid_cliente', sql.Int, uid_cliente)
            .query('SELECT uid_cliente FROM tbl_clientes WHERE uid_cliente = @uid_cliente');
        if (cli.recordset.length === 0) throw { status: 404, error: 'Cliente no encontrado' };

        const corr = await new sql.Request(tx)
            .input('serie', sql.NVarChar, SERIE_INICIAL)
            .query(`SELECT MAX(uid_pedido) AS ultimo FROM tbl_mpedidos WITH (UPDLOCK, HOLDLOCK)
                    WHERE uid_pedido >= @serie`);
        const ultimo = corr.recordset[0].ultimo;
        const uid_pedido = ultimo ? String(parseInt(ultimo, 10) + 1).padStart(7, '0') : SERIE_INICIAL;

        const lineas = await calcularLineas(tx, items);
        const subtotal = round2(lineas.reduce((s, l) => s + l.total, 0));

        await new sql.Request(tx)
            .input('CodAlmacen', sql.Int, COD_ALMACEN)
            .input('uid_pedido', sql.NVarChar, uid_pedido)
            .input('uid_cliente', sql.Int, uid_cliente)
            .input('tipodoc', sql.NVarChar, TIPODOC)
            .input('id_status', sql.NVarChar, STATUS_EN_PROCESO)
            .input('observaciones', sql.NVarChar, (observaciones || '').trim() || 'SIN COMENTARIOS')
            .input('TotalItems', sql.Int, lineas.length)
            .input('tipopago', sql.NVarChar, TIPOPAGO)
            .input('plazo', sql.NVarChar, PLAZO)
            .input('subtotal', sql.Money, subtotal)
            .input('total', sql.Money, subtotal)
            .input('uid_usuario', sql.Int, uid_usuario)
            .input('workstation', sql.NVarChar, WORKSTATION)
            .input('ipaddress', sql.NVarChar, ipCliente(req))
            .input('uid_vendedor', sql.NVarChar, String(req.vendedor.uid_vendedor))
            .query(`
                INSERT INTO tbl_mpedidos (
                    CodAlmacen, uid_pedido, uid_cliente, tipodoc, fecha_pedido, id_status,
                    facturado, observaciones, facturable, TotalItems, tipopago, plazo,
                    pdescuento, descuento, subtotal, iva, bimponible, total,
                    uid_usuario, workstation, ipaddress, fecreg, fecmod, uid_vendedor
                ) VALUES (
                    @CodAlmacen, @uid_pedido, @uid_cliente, @tipodoc, GETDATE(), @id_status,
                    0, @observaciones, 1, @TotalItems, @tipopago, @plazo,
                    0, 0, @subtotal, 0, 0, @total,
                    @uid_usuario, @workstation, @ipaddress, GETDATE(), GETDATE(), @uid_vendedor
                )`);

        await insertarDetalle(tx, uid_pedido, lineas, uid_usuario);

        if (client_uuid) {
            await new sql.Request(tx)
                .input('client_uuid', sql.NVarChar(36), client_uuid)
                .input('uid_pedido', sql.NVarChar, uid_pedido)
                .input('uid_vendedor', sql.NVarChar, uid_vendedor)
                .input('total', sql.Money, subtotal)
                .input('total_items', sql.Int, lineas.length)
                .query(`INSERT INTO tbl_app_idempotencia (client_uuid, uid_pedido, uid_vendedor, total, total_items, fecreg)
                        VALUES (@client_uuid, @uid_pedido, @uid_vendedor, @total, @total_items, GETDATE())`);
        }

        await tx.commit();
        res.status(201).json({ mensaje: 'Pedido creado', uid_pedido, total: subtotal, items: lineas.length });
    } catch (error) {
        try { await tx.rollback(); } catch (_) { /* ya revertida */ }
        logError('POST /pedidos', req, error);

        // Red de seguridad: si aun así chocó la PK del uuid (2627), devolver el existente.
        if (client_uuid && error && error.number === 2627) {
            try {
                const previo = await pool.request()
                    .input('client_uuid', sql.NVarChar(36), client_uuid)
                    .query('SELECT uid_pedido, total, total_items FROM tbl_app_idempotencia WHERE client_uuid = @client_uuid');
                if (previo.recordset.length > 0) return res.status(200).json(respuestaReplay(previo.recordset[0]));
            } catch (_) { /* cae al error genérico */ }
        }
        // Tabla auxiliar ausente en este tenant: mensaje claro en vez de un 500 críptico
        if (client_uuid && error && error.number === 208) {
            return res.status(500).json({ error: 'Falta tbl_app_idempotencia en esta empresa (ejecutar sql/001_tbl_app_idempotencia.sql)' });
        }
        responderError(res, error, 'POST /pedidos', req);
    }
});

// ----------------------------------------------------------------- PUT
// Solo pedidos del vendedor en estado EN PROCESO.
// body: { observaciones?, items: [{ coditems, cajas, botellas }] }
router.put('/pedidos/:id', verificarToken, async (req, res) => {
    const { observaciones, items } = req.body;
    const uid_pedido = req.params.id;
    const pool = await getConnection(req.empresa);
    const tx = new sql.Transaction(pool);
    const uid_usuario = parseInt(req.vendedor.uid_vendedor);

    try {
        await tx.begin(sql.ISOLATION_LEVEL.SERIALIZABLE);

        const cab = await new sql.Request(tx)
            .input('id', sql.NVarChar, uid_pedido)
            .input('uid_vendedor', sql.NVarChar, String(req.vendedor.uid_vendedor))
            .query(`SELECT id_status, uid_vendedor, observaciones FROM tbl_mpedidos WITH (UPDLOCK)
                    WHERE uid_pedido = @id AND CodAlmacen = ${COD_ALMACEN}`);
        if (cab.recordset.length === 0) throw { status: 404, error: 'Pedido no encontrado' };
        const actual = cab.recordset[0];
        if (String(actual.uid_vendedor).trim() !== String(req.vendedor.uid_vendedor)) {
            throw { status: 403, error: 'El pedido no pertenece a este vendedor' };
        }
        if (actual.id_status !== STATUS_EN_PROCESO) {
            throw { status: 409, error: 'El pedido ya no está en proceso y no se puede modificar' };
        }

        const lineas = await calcularLineas(tx, items);
        const subtotal = round2(lineas.reduce((s, l) => s + l.total, 0));

        await new sql.Request(tx)
            .input('id', sql.NVarChar, uid_pedido)
            .query(`DELETE FROM tbl_dpedidos WHERE uid_pedido = @id AND codalmacen = ${COD_ALMACEN}`);
        await insertarDetalle(tx, uid_pedido, lineas, uid_usuario);

        const obs = observaciones === undefined ? actual.observaciones
            : ((observaciones || '').trim() || 'SIN COMENTARIOS');
        await new sql.Request(tx)
            .input('id', sql.NVarChar, uid_pedido)
            .input('observaciones', sql.NVarChar, obs)
            .input('TotalItems', sql.Int, lineas.length)
            .input('subtotal', sql.Money, subtotal)
            .input('total', sql.Money, subtotal)
            .input('uid_usuario', sql.Int, uid_usuario)
            .input('ipaddress', sql.NVarChar, ipCliente(req))
            .query(`
                UPDATE tbl_mpedidos
                SET observaciones = @observaciones, TotalItems = @TotalItems,
                    subtotal = @subtotal, total = @total,
                    uid_usuario = @uid_usuario, ipaddress = @ipaddress, fecmod = GETDATE()
                WHERE uid_pedido = @id AND CodAlmacen = ${COD_ALMACEN}`);

        await tx.commit();
        res.json({ mensaje: 'Pedido actualizado', uid_pedido, total: subtotal, items: lineas.length });
    } catch (error) {
        try { await tx.rollback(); } catch (_) { /* ya revertida */ }
        responderError(res, error, 'PUT /pedidos/:id', req);
    }
});

// ----------------------------------------------------------------- GET lista
// query: status=00|02|04|99 (opcional), buscar=texto (número o cliente), desde=YYYY-MM-DD, hasta=YYYY-MM-DD
router.get('/pedidos', verificarToken, async (req, res) => {
    try {
        const { status, buscar, desde, hasta } = req.query;
        const pool = await getConnection(req.empresa);
        const request = pool.request()
            .input('uid_vendedor', sql.NVarChar, String(req.vendedor.uid_vendedor));

        let where = `m.uid_vendedor = @uid_vendedor AND m.tipodoc = '${TIPODOC}'`;
        if (status) {
            request.input('status', sql.NVarChar, String(status));
            where += ' AND m.id_status = @status';
        }
        if (buscar) {
            request.input('buscar', sql.NVarChar, `%${String(buscar).trim()}%`);
            where += ` AND (m.uid_pedido LIKE @buscar
                        OR c.str_cliente_nombres LIKE @buscar
                        OR c.str_cliente_apellidos LIKE @buscar
                        OR c.str_cliente_cedula LIKE @buscar)`;
        }
        if (desde) {
            request.input('desde', sql.Date, desde);
            where += ' AND m.fecha_pedido >= @desde';
        }
        if (hasta) {
            request.input('hasta', sql.Date, hasta);
            where += ' AND m.fecha_pedido < DATEADD(day, 1, @hasta)';
        }

        const result = await request.query(`
            SELECT TOP 200 m.uid_pedido, m.fecha_pedido, m.id_status, s.descripcion AS status,
                   m.uid_cliente, c.str_cliente_nombres, c.str_cliente_apellidos,
                   m.TotalItems, m.total, m.observaciones, m.facturado, m.numfactu
            FROM tbl_mpedidos m
            LEFT JOIN tbl_clientes c ON c.uid_cliente = m.uid_cliente
            LEFT JOIN tbl_statusdoc s ON s.id_status = m.id_status
            WHERE ${where}
            ORDER BY m.uid_pedido DESC`);
        res.json(result.recordset);
    } catch (error) {
        responderError(res, error, 'GET /pedidos', req);
    }
});

// ----------------------------------------------------------------- GET detalle
router.get('/pedidos/:id', verificarToken, async (req, res) => {
    try {
        const pool = await getConnection(req.empresa);
        const cab = await pool.request()
            .input('id', sql.NVarChar, req.params.id)
            .query(`
                SELECT m.*, s.descripcion AS status,
                       c.str_cliente_nombres, c.str_cliente_apellidos, c.str_cliente_direccion,
                       c.str_cliente_cedula, c.str_cliente_tipo_cedula
                FROM tbl_mpedidos m
                LEFT JOIN tbl_clientes c ON c.uid_cliente = m.uid_cliente
                LEFT JOIN tbl_statusdoc s ON s.id_status = m.id_status
                WHERE m.uid_pedido = @id AND m.CodAlmacen = ${COD_ALMACEN}`);
        if (cab.recordset.length === 0) {
            return res.status(404).json({ error: 'Pedido no encontrado' });
        }
        // El detalle incluye datos actuales del producto para poder editar el pedido en la app
        const det = await pool.request()
            .input('id', sql.NVarChar, req.params.id)
            .query(`
                SELECT d.coditems, d.descripcion, d.cantidad, d.cantidad_unidad, d.unidad_total,
                       d.precunit, d.total,
                       i.DOLpre, i.DOLofe, i.DOLmay, i.DOLdis, i.DOLesp,
                       i.cantunidad, i.VentaBotella, i.VentaCaja, i.activo,
                       l.Nombre_Linea, p.Nombre_Presentacion
                FROM tbl_dpedidos d
                LEFT JOIN tbl_items i ON i.coditems = d.coditems
                LEFT JOIN tbl_linea l ON i.Cod_Linea = l.Cod_Linea
                LEFT JOIN tbl_presentacion p ON i.Cod_Presentacion = p.Cod_Presentacion
                WHERE d.uid_pedido = @id AND d.codalmacen = ${COD_ALMACEN}
                ORDER BY d.coditems`);
        res.json({ ...cab.recordset[0], items: det.recordset });
    } catch (error) {
        responderError(res, error, 'GET /pedidos/:id', req);
    }
});

// ----------------------------------------------------------------- DELETE (anular)
router.delete('/pedidos/:id', verificarToken, async (req, res) => {
    try {
        const pool = await getConnection(req.empresa);
        const result = await pool.request()
            .input('id', sql.NVarChar, req.params.id)
            .input('uid_vendedor', sql.NVarChar, String(req.vendedor.uid_vendedor))
            .input('motivo', sql.NVarChar, (req.body && req.body.motivo) || 'Anulado desde la app')
            .query(`
                UPDATE tbl_mpedidos
                SET id_status = '${STATUS_ANULADO}', fecha_anula = GETDATE(), motivo_anula = @motivo, fecmod = GETDATE()
                WHERE uid_pedido = @id AND CodAlmacen = ${COD_ALMACEN}
                  AND uid_vendedor = @uid_vendedor AND id_status = '${STATUS_EN_PROCESO}'`);
        if (result.rowsAffected[0] === 0) {
            return res.status(409).json({ error: 'El pedido no existe, no es suyo o ya no está en proceso' });
        }
        res.json({ mensaje: 'Pedido anulado', uid_pedido: req.params.id });
    } catch (error) {
        responderError(res, error, 'DELETE /pedidos/:id', req);
    }
});

module.exports = router;
