const express = require('express');
const { getConnection, sql } = require('../config/database');
const { verificarToken } = require('../middleware/auth');

const router = express.Router();

// Constantes del módulo (valores observados en tbl_mpago del VB6, cobro 0004839)
const COD_ALMACEN = 1;
const SERIE_INICIAL = '9000001';   // serie propia de la app en tbl_mpago, no toca el correlativo del VB6
const STATUS_EN_PROCESO = '02';    // fecha_cierre NULL: la oficina lo cierra desde InvenSoft (pasa a 06)
const STATUS_CERRADO = '06';
const STATUS_ANULADO = '99';
const WORKSTATION = 'APP-MOVIL';
// uid_usuario es el OPERADOR de InvenSoft (tbl_usuarios), no el vendedor. Igual que pedidos.js.
const UID_USUARIO_APP = 1;   // ADMIN

// Formas de pago (tbl_generalcodes, reference='formapago')
const FP_TARJETA = '01';
const FP_PAGO_MOVIL = '02';
const FP_DIVISAS = '03';        // DOLARES: efectivo en divisas, sin banco ni tasa
const FP_EFECTIVO_BS = '04';
const FP_DESCUENTO = '05';
// Regla de Sabino: todo lo que entra por un banco nacional es en bolívares
// y exige fijar la tasa del día; lo que se paga en dólares va como divisas,
// sin banco y sin tasa.
const FORMAS_EN_BS = [FP_TARJETA, FP_PAGO_MOVIL, FP_EFECTIVO_BS];

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

function respuestaReplay(fila) {
    return {
        mensaje: 'Cobro ya registrado',
        numpago: fila.numpago,
        monto: Number(fila.monto),
        replay: true
    };
}

function logError(donde, req, error) {
    const emp = (req && req.empresa) || '?';
    const ven = (req && req.vendedor && req.vendedor.uid_vendedor) || '?';
    console.error(`[${new Date().toISOString()}] ${donde} empresa=${emp} vendedor=${ven} ` +
        `number=${error && error.number} -> ${error && (error.message || error.error)}`);
    if (error && error.stack) console.error(error.stack);
}

function responderError(res, error, donde, req) {
    if (error && error.status) return res.status(error.status).json({ error: error.error });
    if (donde) logError(donde, req, error);
    return res.status(500).json({ error: error.message || 'Error interno' });
}

// La letra del vendedor (tbl_vendedor.letra) es la que el VB6 escribe en
// dpago/dfpago. No viaja en el JWT (tokens viejos no la traen), se consulta aquí.
async function letraVendedor(tx, uid_vendedor) {
    const r = await new sql.Request(tx)
        .input('uid', sql.NVarChar, String(uid_vendedor))
        .query('SELECT letra FROM tbl_vendedor WHERE uid_vendedor = @uid');
    if (r.recordset.length === 0) throw { status: 401, error: 'Vendedor no encontrado' };
    const letra = (r.recordset[0].letra || '').toString().trim();
    if (!letra) throw { status: 400, error: 'El vendedor no tiene letra asignada en el sistema' };
    return letra;
}

// Catálogo activo de generalcodes por reference. Devuelve { code: name }.
async function catalogo(reqSql, reference) {
    const r = await reqSql
        .input('ref', sql.NVarChar, reference)
        .query(`SELECT code, name FROM tbl_generalcodes
                WHERE reference = @ref AND estado = '1' ORDER BY code`);
    const map = {};
    r.recordset.forEach(f => { map[String(f.code).trim()] = String(f.name).trim(); });
    return map;
}

/**
 * Valida los documentos a abonar contra tbl_CtasxCobrar.
 * - El documento debe pertenecer al cliente y tener saldo.
 * - El abono no puede superar el saldo menos lo que ya está EN PROCESO
 *   (evita que el vendedor registre dos veces el mismo cobro).
 * Lanza { status, error } si algo no es válido.
 */
async function validarDocumentos(tx, codclien, documentos) {
    if (!Array.isArray(documentos) || documentos.length === 0) {
        throw { status: 400, error: 'El cobro debe abonar al menos un documento' };
    }
    const vistos = new Set();
    const lineas = [];
    for (const d of documentos) {
        const tipodoc = String(d.tipodoc || '').trim();
        const iddoc = String(d.iddoc || '').trim();
        const monto = round2(Number(d.monto) || 0);
        const llave = `${tipodoc}-${iddoc}`;

        if (!tipodoc || !iddoc) throw { status: 400, error: 'Documento sin tipodoc o iddoc' };
        if (vistos.has(llave)) throw { status: 400, error: `Documento ${llave} repetido en el cobro` };
        vistos.add(llave);
        if (monto <= 0) throw { status: 400, error: `Monto inválido en documento ${iddoc}` };

        // UPDLOCK: dos cobros simultáneos sobre la misma factura se serializan aquí.
        const r = await new sql.Request(tx)
            .input('codalmacen', sql.Int, COD_ALMACEN)
            .input('codclien', sql.Int, codclien)
            .input('tipodoc', sql.NVarChar, tipodoc)
            .input('iddoc', sql.NVarChar, iddoc)
            .query(`
                SELECT x.SaldoActual,
                       ISNULL((SELECT SUM(dp.monto)
                               FROM tbl_dpago dp
                               INNER JOIN tbl_mpago mp
                                   ON mp.numpago = dp.numpago AND mp.codalmacen = dp.codalmacen
                               WHERE dp.codalmacen = x.codalmacen
                                 AND dp.tipodoc = x.tipodoc AND dp.iddoc = x.iddoc
                                 AND mp.status = '${STATUS_EN_PROCESO}'), 0) AS en_proceso
                FROM tbl_CtasxCobrar x WITH (UPDLOCK, HOLDLOCK)
                WHERE x.codalmacen = @codalmacen AND x.uid_cliente = @codclien
                  AND x.tipodoc = @tipodoc AND x.iddoc = @iddoc`);
        if (r.recordset.length === 0) {
            throw { status: 404, error: `Documento ${tipodoc}-${iddoc} no existe en la deuda del cliente` };
        }
        const saldo = round2(Number(r.recordset[0].SaldoActual) || 0);
        const enProceso = round2(Number(r.recordset[0].en_proceso) || 0);
        const disponible = round2(saldo - enProceso);
        if (monto > disponible + 0.005) {
            const detalle = enProceso > 0
                ? `saldo ${saldo.toFixed(2)} con ${enProceso.toFixed(2)} ya en proceso`
                : `saldo ${saldo.toFixed(2)}`;
            throw { status: 409, error: `El abono a ${iddoc} (${monto.toFixed(2)}) supera el disponible: ${detalle}` };
        }
        lineas.push({ tipodoc, iddoc, monto });
    }
    return lineas;
}

/**
 * Valida las formas de pago contra tbl_generalcodes y arma las filas de tbl_dfpago.
 * Reglas (definidas por Sabino):
 *  - Formas en bolívares (01 tarjeta, 02 pago móvil, 04 efectivo Bs.): exigen tasa
 *    del día (`cambio`). El vendedor puede enviar el monto en USD (`monto`) o en
 *    bolívares (`montobs`); el que falte se calcula con la tasa.
 *  - Pago móvil (02): regla confirmada por Sabino (21/09, ejemplo 9000009):
 *    él registra el banco DEL CLIENTE (emisor) y el número de transacción en
 *    su campo. Por eso: codbanco = banco emisor (catálogo), nrotrans = los
 *    últimos dígitos, y referencia = "PM {BANCO RECEPTOR} {dígitos}" para no
 *    perder dónde cayó el dinero. La app sigue mandando lo mismo de siempre
 *    (codbanco = receptor, banco_emisor, referencia_digitos); el remapeo es aquí.
 *  - Divisas (03): efectivo en dólares, sin banco y sin tasa.
 *  - Descuento (05): el vendedor puede otorgarlo SOLO cuando el cliente paga
 *    en dólares (regla de Sabino). Participa del cuadre como en el VB6
 *    (ej. cobro 0004838: $695 = $28.50 PM + $600 divisas + $66.50 descuento),
 *    referencia "DSCTO.% {pct} # {iddoc}". También se acepta con monto 0
 *    (informativo). [lineasDoc] se usa para armar la referencia.
 */
async function validarFormas(tx, formas, lineasDoc) {
    if (!Array.isArray(formas) || formas.length === 0) {
        throw { status: 400, error: 'El cobro debe indicar al menos una forma de pago' };
    }
    const formasCat = await catalogo(new sql.Request(tx), 'formapago');
    const bancosCat = await catalogo(new sql.Request(tx), 'banco');

    const filas = [];
    for (const f of formas) {
        const cod = String(f.codformapago || '').trim();
        const nombreForma = formasCat[cod];
        if (!nombreForma) throw { status: 400, error: `Forma de pago inválida: ${cod}` };

        const esBs = FORMAS_EN_BS.indexOf(cod) !== -1;
        let nrotrans = null;
        let codbancoFila = null;
        const cambio = f.cambio === undefined || f.cambio === null ? null : round2(Number(f.cambio));
        const codbanco = f.codbanco ? String(f.codbanco).trim() : null;
        let referencia = (f.referencia || '').toString().trim();
        let monto = f.monto === undefined || f.monto === null ? null : round2(Number(f.monto));
        let montobs = f.montobs === undefined || f.montobs === null ? null : round2(Number(f.montobs));

        if (codbanco && !bancosCat[codbanco]) {
            throw { status: 400, error: `Banco inválido: ${codbanco}` };
        }

        // --- Descuento: solo cuando el cliente paga en dólares (regla de Sabino)
        if (cod === FP_DESCUENTO) {
            if (cambio !== null && cambio > 0) {
                throw { status: 400, error: 'El descuento no lleva tasa de cambio' };
            }
            if (codbanco) {
                throw { status: 400, error: 'El descuento no lleva banco' };
            }
            const montoDcto = monto === null ? 0 : monto;
            if (montoDcto < 0) throw { status: 400, error: 'Monto inválido en el descuento' };
            if (!referencia) {
                // Mismo formato que usa el VB6: "DSCTO.% 10 # 0013521"
                const pct = f.descuento_pct === undefined || f.descuento_pct === null
                    ? null : round2(Number(f.descuento_pct));
                const iddocRef = (lineasDoc && lineasDoc.length > 0) ? lineasDoc[0].iddoc : '';
                referencia = pct !== null && pct > 0
                    ? `DSCTO.% ${pct} # ${iddocRef}`.trim()
                    : (iddocRef ? `DSCTO. # ${iddocRef}` : 'DSCTO.');
            }
            filas.push({
                codformapago: cod, nombre: nombreForma, monto: montoDcto,
                cambio: null, montobs: null, codbanco: null,
                referencia: referencia.slice(0, 50)
            });
            continue;
        }

        // --- Formas en bolívares: la tasa del día es obligatoria
        if (esBs) {
            if (cambio === null || cambio <= 0) {
                throw { status: 400, error: `${nombreForma}: es un pago en bolívares, debe indicar la tasa del día` };
            }
            // El vendedor puede cobrar pensando en bolívares o en dólares:
            // se acepta cualquiera de los dos y el otro se deriva con la tasa.
            if ((monto === null || monto <= 0) && montobs !== null && montobs > 0) {
                monto = round2(montobs / cambio);
            } else if (monto !== null && monto > 0) {
                montobs = round2(monto * cambio);
            } else {
                throw { status: 400, error: `${nombreForma}: falta el monto (en dólares o en bolívares)` };
            }
        } else {
            // --- Divisas (03) y cualquier otra forma en dólares: sin banco ni tasa
            if (cambio !== null && cambio > 0) {
                throw { status: 400, error: `${nombreForma}: un pago en divisas no lleva tasa de cambio` };
            }
            if (codbanco) {
                throw { status: 400, error: `${nombreForma}: un pago en divisas no lleva banco` };
            }
            if (monto === null || monto <= 0) {
                throw { status: 400, error: `Monto inválido en ${nombreForma}` };
            }
            montobs = null;
        }

        // --- Pago móvil: banco destino, banco emisor y dígitos de la referencia
        if (cod === FP_PAGO_MOVIL) {
            if (!codbanco) throw { status: 400, error: 'Pago móvil: falta el banco que recibió el pago' };

            const emisor = String(f.banco_emisor || '').trim();
            if (!emisor || !bancosCat[emisor]) {
                throw { status: 400, error: 'Pago móvil: falta el banco desde el que pagó el cliente' };
            }

            const digitos = String(f.referencia_digitos || '').trim();
            if (!/^\d{4,8}$/.test(digitos)) {
                throw { status: 400, error: 'Pago móvil: la referencia debe tener los últimos 4 a 8 dígitos' };
            }
            const nombreReceptor = bancosCat[codbanco] || codbanco || '';
            nrotrans = digitos;                         // el campo "número de transacción" del VB6
            codbancoFila = emisor;                      // el banco DEL CLIENTE, como lo registra Sabino
            referencia = `PM ${nombreReceptor} ${digitos}`.slice(0, 50);
        } else if (cod === FP_TARJETA && !codbanco) {
            throw { status: 400, error: 'Tarjeta de débito: falta el banco del punto de venta' };
        }

        filas.push({
            codformapago: cod,
            nombre: nombreForma,
            monto,
            cambio: esBs ? cambio : null,
            montobs,
            codbanco: cod === FP_PAGO_MOVIL ? codbancoFila : codbanco,
            nrotrans,
            referencia: referencia ? referencia.slice(0, 50) : null
        });
    }

    // Regla de Sabino: el descuento aplica solo cuando el cliente paga en dólares.
    const montoDescuento = filas.filter(x => x.codformapago === FP_DESCUENTO)
        .reduce((s, x) => s + x.monto, 0);
    if (montoDescuento > 0 && !filas.some(x => x.codformapago === FP_DIVISAS && x.monto > 0)) {
        throw { status: 400, error: 'El descuento aplica cuando el cliente paga en dólares: agregue la forma DOLARES' };
    }
    return filas;
}

// ---------------------------------------------------------------- GET catálogos
// Formas de pago y bancos activos para armar el formulario de cobro en la app.
router.get('/cobros/catalogos', verificarToken, async (req, res) => {
    try {
        const pool = await getConnection(req.empresa);
        const formas = await pool.request()
            .input('ref', sql.NVarChar, 'formapago')
            .query(`SELECT code, name FROM tbl_generalcodes
                    WHERE reference = @ref AND estado = '1' ORDER BY code`);
        const bancos = await pool.request()
            .input('ref', sql.NVarChar, 'banco')
            .query(`SELECT code, name FROM tbl_generalcodes
                    WHERE reference = @ref AND estado = '1' ORDER BY name`);
        res.json({
            formas_pago: formas.recordset.map(f => ({ code: String(f.code).trim(), name: String(f.name).trim() })),
            bancos: bancos.recordset.map(b => ({ code: String(b.code).trim(), name: String(b.name).trim() }))
        });
    } catch (error) {
        responderError(res, error, 'GET /cobros/catalogos', req);
    }
});

// ------------------------------------------------- GET cxc del vendedor
// Todas las cuentas por cobrar pendientes de los CLIENTES del vendedor en una
// sola llamada. La app la guarda en su caché local (SQLite) durante el sync de
// catálogos, para poder registrar cobros SIN CONEXIÓN contra el último saldo
// conocido. Misma lógica de VIEW_CtasxCobrar que /clientes/:id/cxc.
// (Declarado antes de /cobros/:id para que Express no lo capture como id.)
router.get('/cobros/cxc-vendedor', verificarToken, async (req, res) => {
    try {
        const pool = await getConnection(req.empresa);
        const r = await pool.request()
            .input('uid_vendedor', sql.NVarChar, String(req.vendedor.uid_vendedor))
            .query(`
                SELECT x.uid_cliente, c.str_cliente_nombres, c.str_cliente_apellidos,
                       x.tipodoc, x.iddoc, d.Nombre AS nombre_doc, d.Abreviatura,
                       d.ValorCxC, x.FechaEmision, x.FechaVencimiento,
                       x.MontoOriginal, x.MontoAbonado, x.SaldoActual,
                       DATEDIFF(day, x.FechaVencimiento, GETDATE()) AS dias_vencido
                FROM tbl_CtasxCobrar x
                INNER JOIN tbl_documentos d ON d.TipoDoc = x.tipodoc
                INNER JOIN tbl_clientes c ON c.uid_cliente = x.uid_cliente
                WHERE x.codalmacen = ${COD_ALMACEN}
                  AND x.SaldoActual > 0
                  AND d.ValorCxC <> 0
                  AND LTRIM(RTRIM(CONVERT(nvarchar(10), c.uid_vendedor))) = @uid_vendedor
                ORDER BY x.uid_cliente, x.FechaVencimiento ASC, x.iddoc ASC`);
        res.json({ generado_en: new Date().toISOString(), documentos: r.recordset });
    } catch (error) {
        responderError(res, error, 'GET /cobros/cxc-vendedor', req);
    }
});

// ---------------------------------------------------------------- POST
// body: {
//   uid_cliente,
//   documentos: [{ tipodoc, iddoc, monto }],           // facturas de tbl_CtasxCobrar
//   formas:     [{ codformapago, monto, cambio?,       // monto siempre en USD
//                  codbanco?, banco_emisor?, referencia_digitos?, referencia? }],
//   observacion?, client_uuid?
// }
// El cobro queda EN PROCESO (status 02, fecha_cierre NULL). NO toca tbl_CtasxCobrar:
// la oficina verifica el pago y cierra la cobranza en InvenSoft (pasa a 06 y salda).
router.post('/cobros', verificarToken, async (req, res) => {
    const { uid_cliente, documentos, formas } = req.body;
    if (!uid_cliente) return res.status(400).json({ error: 'Cliente obligatorio' });

    const client_uuid = normalizarUuid(req.body.client_uuid);
    const pool = await getConnection(req.empresa);
    const tx = new sql.Transaction(pool);
    const uid_vendedor = String(req.vendedor.uid_vendedor);

    try {
        await tx.begin(sql.ISOLATION_LEVEL.SERIALIZABLE);

        // --- Idempotencia: ¿ya se procesó este UUID? ---
        if (client_uuid) {
            const previo = await new sql.Request(tx)
                .input('client_uuid', sql.NVarChar(36), client_uuid)
                .query(`SELECT numpago, monto
                        FROM tbl_app_idempotencia_cobros WITH (UPDLOCK, HOLDLOCK)
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

        const letra = await letraVendedor(tx, uid_vendedor);
        const lineasDoc = await validarDocumentos(tx, uid_cliente, documentos);
        const lineasFp = await validarFormas(tx, formas, lineasDoc);

        // Cuadre: documentos = formas de pago (el descuento va con monto 0)
        const totalDoc = round2(lineasDoc.reduce((s, l) => s + l.monto, 0));
        const totalFp = round2(lineasFp.reduce((s, l) => s + l.monto, 0));
        if (Math.abs(totalDoc - totalFp) > 0.01) {
            throw { status: 400, error: `El cobro no cuadra: documentos ${totalDoc.toFixed(2)} vs formas de pago ${totalFp.toFixed(2)}` };
        }

        // Correlativo propio de la app en tbl_mpago (numpago nvarchar(7))
        const corr = await new sql.Request(tx)
            .input('serie', sql.NVarChar, SERIE_INICIAL)
            .query(`SELECT MAX(numpago) AS ultimo FROM tbl_mpago WITH (UPDLOCK, HOLDLOCK)
                    WHERE numpago >= @serie AND codalmacen = ${COD_ALMACEN}`);
        const ultimo = corr.recordset[0].ultimo;
        const numpago = ultimo ? String(parseInt(ultimo, 10) + 1).padStart(7, '0') : SERIE_INICIAL;

        const ip = ipCliente(req);

        // Encabezado EN PROCESO. saldo=0 y desanul/fechanul NULL como en el VB6.
        // fecha/fecreg van SOLO con la fecha (hora 00:00) porque así las guarda
        // el VB6 (la hora vive en horareg); un datetime con hora rompería los
        // filtros BETWEEN por día de sus reportes.
        await new sql.Request(tx)
            .input('codalmacen', sql.Int, COD_ALMACEN)
            .input('numpago', sql.NVarChar, numpago)
            .input('codclien', sql.Int, uid_cliente)
            .input('monto', sql.Money, totalDoc)
            .input('status', sql.NVarChar, STATUS_EN_PROCESO)
            .input('uid_usuario', sql.Int, UID_USUARIO_APP)
            .input('workstation', sql.NVarChar, WORKSTATION)
            .input('ipaddress', sql.NVarChar, ip)
            .query(`
                INSERT INTO tbl_mpago (
                    codalmacen, numpago, codclien, fecha, monto, status,
                    desanul, fechanul, saldo, fecha_cierre,
                    uid_usuario, workstation, ipaddress, fecreg, horareg
                ) VALUES (
                    @codalmacen, @numpago, @codclien, CONVERT(date, GETDATE()), @monto, @status,
                    NULL, NULL, 0, NULL,
                    @uid_usuario, @workstation, @ipaddress, CONVERT(date, GETDATE()), CONVERT(nvarchar(15), GETDATE(), 108)
                )`);

        // Aplicación a documentos (tbl_dpago)
        for (const l of lineasDoc) {
            await new sql.Request(tx)
                .input('codalmacen', sql.Int, COD_ALMACEN)
                .input('numpago', sql.NVarChar, numpago)
                .input('tipodoc', sql.NVarChar, l.tipodoc)
                .input('iddoc', sql.NVarChar, l.iddoc)
                .input('monto', sql.Money, l.monto)
                .input('uid_usuario', sql.Int, UID_USUARIO_APP)
                .input('workstation', sql.NVarChar, WORKSTATION)
                .input('ipaddress', sql.NVarChar, ip)
                .input('vend_letra', sql.Char(2), letra)
                .query(`
                    INSERT INTO tbl_dpago (
                        codalmacen, numpago, tipodoc, iddoc, monto, fecha,
                        uid_usuario, workstation, ipaddress, fecreg, horareg, vend_letra
                    ) VALUES (
                        @codalmacen, @numpago, @tipodoc, @iddoc, @monto, CONVERT(date, GETDATE()),
                        @uid_usuario, @workstation, @ipaddress, CONVERT(date, GETDATE()), CONVERT(nvarchar(15), GETDATE(), 108), @vend_letra
                    )`);
        }

        // Formas de pago (tbl_dfpago)
        for (const f of lineasFp) {
            await new sql.Request(tx)
                .input('codalmacen', sql.Int, COD_ALMACEN)
                .input('numpago', sql.NVarChar, numpago)
                .input('vend_letra', sql.Char(2), letra)
                .input('codformapago', sql.NVarChar, f.codformapago)
                .input('referencia', sql.NVarChar, f.referencia)
                .input('codbanco', sql.NVarChar, f.codbanco)
                .input('cambio', sql.Money, f.cambio)
                .input('montobs', sql.Money, f.montobs)
                .input('monto', sql.Money, f.monto)
                .input('uid_usuario', sql.Int, UID_USUARIO_APP)
                .input('workstation', sql.NVarChar, WORKSTATION)
                .input('ipaddress', sql.NVarChar, ip)
                .input('nrotrans', sql.NVarChar, f.nrotrans || null)
                .query(`
                    INSERT INTO tbl_dfpago (
                        codalmacen, numpago, vend_letra, codformapago, fecha, referencia,
                        codbanco, cambio, montobs, monto,
                        uid_usuario, workstation, ipaddress, fecreg, horareg, nrotrans
                    ) VALUES (
                        @codalmacen, @numpago, @vend_letra, @codformapago, CONVERT(date, GETDATE()), @referencia,
                        @codbanco, @cambio, @montobs, @monto,
                        @uid_usuario, @workstation, @ipaddress, CONVERT(date, GETDATE()), CONVERT(nvarchar(15), GETDATE(), 108), @nrotrans
                    )`);
        }

        if (client_uuid) {
            await new sql.Request(tx)
                .input('client_uuid', sql.NVarChar(36), client_uuid)
                .input('numpago', sql.NVarChar, numpago)
                .input('uid_vendedor', sql.NVarChar, uid_vendedor)
                .input('monto', sql.Money, totalDoc)
                .query(`INSERT INTO tbl_app_idempotencia_cobros (client_uuid, numpago, uid_vendedor, monto, fecreg)
                        VALUES (@client_uuid, @numpago, @uid_vendedor, @monto, GETDATE())`);
        }

        await tx.commit();
        res.status(201).json({
            mensaje: 'Cobro registrado, pendiente de confirmación en oficina',
            numpago,
            monto: totalDoc,
            documentos: lineasDoc.length,
            formas: lineasFp.length
        });
    } catch (error) {
        try { await tx.rollback(); } catch (_) { /* ya revertida */ }
        logError('POST /cobros', req, error);

        // Red de seguridad: si aun así chocó la PK del uuid (2627), devolver el existente.
        if (client_uuid && error && error.number === 2627) {
            try {
                const previo = await pool.request()
                    .input('client_uuid', sql.NVarChar(36), client_uuid)
                    .query('SELECT numpago, monto FROM tbl_app_idempotencia_cobros WHERE client_uuid = @client_uuid');
                if (previo.recordset.length > 0) return res.status(200).json(respuestaReplay(previo.recordset[0]));
            } catch (_) { /* cae al error genérico */ }
        }
        if (client_uuid && error && error.number === 208) {
            return res.status(500).json({ error: 'Falta tbl_app_idempotencia_cobros en esta empresa (ejecutar sql/002_tbl_app_idempotencia_cobros.sql)' });
        }
        responderError(res, error, 'POST /cobros', req);
    }
});

// ----------------------------------------------------------------- GET lista
// Cobros del vendedor (por su letra en tbl_dpago: incluye los que registre
// la oficina para sus clientes). query: status=02|06|99, desde, hasta, buscar
router.get('/cobros', verificarToken, async (req, res) => {
    try {
        const { status, buscar, desde, hasta } = req.query;
        const pool = await getConnection(req.empresa);

        // Se filtra por los CLIENTES del vendedor, no por vend_letra:
        // la letra se repite entre vendedores (p. ej. MARCO y LUIS VERA son 'D'),
        // así que filtrar por ella dejaría a uno viendo los cobros del otro.
        const request = pool.request()
            .input('uid_vendedor', sql.NVarChar, String(req.vendedor.uid_vendedor));
        let where = `m.codalmacen = ${COD_ALMACEN}
            AND LTRIM(RTRIM(CONVERT(nvarchar(10), c.uid_vendedor))) = @uid_vendedor`;
        if (status) {
            request.input('status', sql.NVarChar, String(status));
            where += ' AND m.status = @status';
        }
        if (buscar) {
            request.input('buscar', sql.NVarChar, `%${String(buscar).trim()}%`);
            where += ` AND (m.numpago LIKE @buscar
                        OR c.str_cliente_nombres LIKE @buscar
                        OR c.str_cliente_apellidos LIKE @buscar
                        OR c.str_cliente_cedula LIKE @buscar)`;
        }
        if (desde) {
            request.input('desde', sql.Date, desde);
            where += ' AND m.fecha >= @desde';
        }
        if (hasta) {
            request.input('hasta', sql.Date, hasta);
            where += ' AND m.fecha < DATEADD(day, 1, @hasta)';
        }

        const result = await request.query(`
            SELECT TOP 200 m.numpago, m.fecha, m.monto, m.status,
                   CASE m.status WHEN '${STATUS_EN_PROCESO}' THEN 'EN PROCESO'
                                 WHEN '${STATUS_CERRADO}' THEN 'CONFIRMADO'
                                 WHEN '${STATUS_ANULADO}' THEN 'ANULADO'
                                 ELSE m.status END AS status_desc,
                   m.fecha_cierre, m.workstation,
                   m.codclien, c.str_cliente_nombres, c.str_cliente_apellidos
            FROM tbl_mpago m
            INNER JOIN tbl_clientes c ON c.uid_cliente = m.codclien
            WHERE ${where}
            ORDER BY m.numpago DESC`);
        res.json(result.recordset);
    } catch (error) {
        responderError(res, error, 'GET /cobros', req);
    }
});

// ----------------------------------------------------------------- GET detalle
router.get('/cobros/:id', verificarToken, async (req, res) => {
    try {
        const pool = await getConnection(req.empresa);
        const cab = await pool.request()
            .input('id', sql.NVarChar, req.params.id)
            .query(`
                SELECT m.numpago, m.fecha, m.monto, m.status,
                       CASE m.status WHEN '${STATUS_EN_PROCESO}' THEN 'EN PROCESO'
                                     WHEN '${STATUS_CERRADO}' THEN 'CONFIRMADO'
                                     WHEN '${STATUS_ANULADO}' THEN 'ANULADO'
                                     ELSE m.status END AS status_desc,
                       m.fecha_cierre, m.desanul, m.fechanul, m.workstation,
                       m.codclien, c.str_cliente_nombres, c.str_cliente_apellidos,
                       c.str_cliente_cedula, c.str_cliente_tipo_cedula, c.str_cliente_direccion
                FROM tbl_mpago m
                LEFT JOIN tbl_clientes c ON c.uid_cliente = m.codclien
                WHERE m.numpago = @id AND m.codalmacen = ${COD_ALMACEN}`);
        if (cab.recordset.length === 0) {
            return res.status(404).json({ error: 'Cobro no encontrado' });
        }

        const docs = await pool.request()
            .input('id', sql.NVarChar, req.params.id)
            .query(`
                SELECT d.tipodoc, d.iddoc, d.monto, td.Nombre AS nombre_doc, td.Abreviatura,
                       x.MontoOriginal, x.SaldoActual, x.FechaEmision, x.FechaVencimiento
                FROM tbl_dpago d
                LEFT JOIN tbl_documentos td ON td.TipoDoc = d.tipodoc
                LEFT JOIN tbl_CtasxCobrar x ON x.codalmacen = d.codalmacen
                     AND x.tipodoc = d.tipodoc AND x.iddoc = d.iddoc
                WHERE d.numpago = @id AND d.codalmacen = ${COD_ALMACEN}
                ORDER BY d.iddoc`);

        const formas = await pool.request()
            .input('id', sql.NVarChar, req.params.id)
            .query(`
                SELECT f.codformapago, gf.name AS forma_pago, f.monto, f.cambio, f.montobs,
                       f.codbanco, gb.name AS banco, f.referencia, f.nrotrans
                FROM tbl_dfpago f
                LEFT JOIN tbl_generalcodes gf ON gf.reference = 'formapago' AND gf.code = f.codformapago
                LEFT JOIN tbl_generalcodes gb ON gb.reference = 'banco' AND gb.code = f.codbanco
                WHERE f.numpago = @id AND f.codalmacen = ${COD_ALMACEN}
                ORDER BY f.codformapago`);

        res.json({ ...cab.recordset[0], documentos: docs.recordset, formas: formas.recordset });
    } catch (error) {
        responderError(res, error, 'GET /cobros/:id', req);
    }
});

// ----------------------------------------------------------------- DELETE (anular)
// Solo cobros creados por la app (workstation APP-MOVIL), del vendedor, EN PROCESO.
router.delete('/cobros/:id', verificarToken, async (req, res) => {
    try {
        const pool = await getConnection(req.empresa);

        // Solo cobros de clientes de este vendedor (ver nota en GET /cobros sobre vend_letra)
        const result = await pool.request()
            .input('id', sql.NVarChar, req.params.id)
            .input('uid_vendedor', sql.NVarChar, String(req.vendedor.uid_vendedor))
            .input('motivo', sql.NVarChar, ((req.body && req.body.motivo) || 'Anulado desde la app').slice(0, 255))
            .query(`
                UPDATE tbl_mpago
                SET status = '${STATUS_ANULADO}', desanul = @motivo, fechanul = CONVERT(date, GETDATE())
                WHERE numpago = @id AND codalmacen = ${COD_ALMACEN}
                  AND status = '${STATUS_EN_PROCESO}' AND workstation = '${WORKSTATION}'
                  AND EXISTS (SELECT 1 FROM tbl_clientes c
                              WHERE c.uid_cliente = tbl_mpago.codclien
                                AND LTRIM(RTRIM(CONVERT(nvarchar(10), c.uid_vendedor))) = @uid_vendedor)`);
        if (result.rowsAffected[0] === 0) {
            return res.status(409).json({ error: 'El cobro no existe, no es suyo, no es de la app o ya no está en proceso' });
        }
        res.json({ mensaje: 'Cobro anulado', numpago: req.params.id });
    } catch (error) {
        responderError(res, error, 'DELETE /cobros/:id', req);
    }
});

module.exports = router;
