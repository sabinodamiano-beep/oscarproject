const express = require('express');
const { getConnection, sql } = require('../config/database');
const { verificarToken } = require('../middleware/auth');

const router = express.Router();

// Mismo almacén que usa el resto de la app (ver routes/pedidos.js)
const COD_ALMACEN = 1;

// Listar clientes con búsqueda
router.get('/clientes', verificarToken, async (req, res) => {
    try {
        const { buscar, todos } = req.query;
        const pool = await getConnection(req.empresa);

        // ?todos=1 -> catálogo completo para la caché offline de la app (sin TOP)
        const completo = String(todos) === '1';

        let query = `
            SELECT ${completo ? '' : 'TOP 50 '}uid_cliente, str_cliente_codigo, str_cliente_cedula, 
                   str_cliente_tipo_cedula, str_cliente_nombres, str_cliente_apellidos,
                   str_cliente_telefono_celular, str_cliente_telefono_casa,
                   str_cliente_direccion, str_cliente_email, str_cliente_comentario,
                   str_cliente_status, dte_cliente_ingreso
            FROM tbl_clientes
        `;

        if (buscar) {
            query += ` WHERE str_cliente_nombres LIKE @buscar 
                       OR str_cliente_apellidos LIKE @buscar
                       OR str_cliente_cedula LIKE @buscar 
                       OR str_cliente_codigo LIKE @buscar`;
        }

        // Para el sync el orden ascendente es estable; para el listado se mantiene el más reciente primero
        query += completo ? ' ORDER BY uid_cliente ASC' : ' ORDER BY uid_cliente DESC';

        const request = pool.request();
        if (buscar) {
            request.input('buscar', sql.NVarChar, `%${buscar}%`);
        }

        const result = await request.query(query);
        res.json(result.recordset);

    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Detalle de un cliente
router.get('/clientes/:id', verificarToken, async (req, res) => {
    try {
        const pool = await getConnection(req.empresa);
        const result = await pool.request()
            .input('id', sql.Int, req.params.id)
            .query('SELECT * FROM tbl_clientes WHERE uid_cliente = @id');

        if (result.recordset.length === 0) {
            return res.status(404).json({ error: 'Cliente no encontrado' });
        }

        res.json(result.recordset[0]);

    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// ----------------------------------------------------- cuentas por cobrar
// Deuda pendiente de un cliente. SOLO LECTURA: replica la lógica de
// VIEW_CtasxCobrar del sistema de escritorio (INNER JOIN con tbl_documentos),
// de modo que la app muestre exactamente el mismo saldo que ve la oficina.
// Los documentos con tipodoc fuera del catálogo (p. ej. 9006, carga
// histórica) quedan excluidos igual que en la vista original.
router.get('/clientes/:id/cxc', verificarToken, async (req, res) => {
    try {
        const pool = await getConnection(req.empresa);
        const result = await pool.request()
            .input('id', sql.Int, req.params.id)
            .input('codalmacen', sql.Int, COD_ALMACEN)
            .query(`
                SELECT x.tipodoc, x.iddoc, d.Nombre AS nombre_doc, d.Abreviatura,
                       d.ValorCxC, x.FechaEmision, x.FechaVencimiento,
                       x.MontoOriginal, x.MontoAbonado, x.SaldoActual,
                       CAST(x.SaldoActual * d.ValorCxC AS money) AS SaldoConSigno,
                       DATEDIFF(day, x.FechaVencimiento, GETDATE()) AS dias_vencido
                FROM tbl_CtasxCobrar x
                INNER JOIN tbl_documentos d ON d.TipoDoc = x.tipodoc
                WHERE x.uid_cliente = @id
                  AND x.codalmacen = @codalmacen
                  AND x.SaldoActual > 0
                  AND d.ValorCxC <> 0
                ORDER BY x.FechaVencimiento ASC, x.iddoc ASC
            `);

        const documentos = result.recordset;
        const totalDeuda = documentos.reduce(
            (acc, d) => acc + Number(d.SaldoConSigno || 0), 0);
        const vencidos = documentos.filter(
            (d) => Number(d.ValorCxC) > 0 && Number(d.dias_vencido) > 0);

        // Últimos documentos ya pagados (SaldoActual = 0), para mostrar
        // historial en clientes solventes. Misma lógica de JOINs.
        // Nota: la tabla no registra la fecha del cobro, solo emisión.
        const pagados = await pool.request()
            .input('id', sql.Int, req.params.id)
            .input('codalmacen', sql.Int, COD_ALMACEN)
            .query(`
                SELECT TOP 10 x.tipodoc, x.iddoc, d.Abreviatura,
                       x.FechaEmision, x.MontoOriginal, x.MontoAbonado
                FROM tbl_CtasxCobrar x
                INNER JOIN tbl_documentos d ON d.TipoDoc = x.tipodoc
                WHERE x.uid_cliente = @id
                  AND x.codalmacen = @codalmacen
                  AND x.SaldoActual = 0
                  AND x.MontoOriginal > 0
                  AND d.ValorCxC > 0
                ORDER BY x.FechaEmision DESC, x.iddoc DESC
            `);

        res.json({
            uid_cliente: parseInt(req.params.id),
            total_deuda: Math.round(totalDeuda * 100) / 100,
            total_documentos: documentos.length,
            documentos_vencidos: vencidos.length,
            monto_vencido: Math.round(
                vencidos.reduce((a, d) => a + Number(d.SaldoActual || 0), 0) * 100) / 100,
            documentos,
            ultimos_pagados: pagados.recordset
        });

    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Crear cliente
router.post('/clientes', verificarToken, async (req, res) => {
    try {
        const {
            tipo_cedula, cedula, nombres, apellidos,
            telefono_celular, telefono_casa, telefono_oficina,
            direccion, email, comentario
        } = req.body;

        if (!nombres || !cedula || !tipo_cedula || !telefono_celular) {
            return res.status(400).json({ error: 'Nombre, cédula, tipo cédula y teléfono celular son obligatorios' });
        }

        const pool = await getConnection(req.empresa);

        // Verificar que la cédula no exista
        const existe = await pool.request()
            .input('cedula', sql.NVarChar, cedula)
            .query('SELECT uid_cliente FROM tbl_clientes WHERE str_cliente_cedula = @cedula');

        if (existe.recordset.length > 0) {
            return res.status(400).json({ error: 'Ya existe un cliente con esa cédula' });
        }

        // Obtener siguiente código de cliente
        const maxCodigo = await pool.request()
            .query('SELECT ISNULL(MAX(uid_cliente), 0) + 1 as siguiente FROM tbl_clientes');
        const siguienteCodigo = maxCodigo.recordset[0].siguiente;
        const codigo = siguienteCodigo.toString().padStart(7, '0');

        const insertResult = await pool.request()
            .input('uid_pais', sql.Int, 212)
            .input('uid_estado', sql.Int, 1)
            .input('uid_ciudad', sql.Int, 49)
            .input('uid_tipocliente', sql.Int, 1)
            .input('uid_usuario', sql.Int, 1)
            .input('uid_vendedor', sql.Int, parseInt(req.vendedor.uid_vendedor))
            .input('CodAlmacen', sql.Int, 1)
            .input('codigo', sql.VarChar, codigo)
            .input('cedula_val', sql.VarChar, cedula)
            .input('tipo_cedula', sql.NVarChar, tipo_cedula)
            .input('nombres', sql.NVarChar, nombres)
            .input('apellidos', sql.NVarChar, apellidos || '.')
            .input('telefono_casa', sql.NVarChar, telefono_casa || '(____)_______')
            .input('telefono_celular', sql.NVarChar, telefono_celular)
            .input('telefono_oficina', sql.NVarChar, telefono_oficina || '(____)_______')
            .input('direccion', sql.NVarChar, direccion || '')
            .input('email', sql.NVarChar, email || '')
            .input('comentario', sql.NVarChar, comentario || 'SIN COMENTARIOS')
            .input('status', sql.NVarChar, '1')
            .query(`
                INSERT INTO tbl_clientes (
                    uid_pais, uid_estado, uid_ciudad, uid_tipocliente,
                    uid_usuario, uid_vendedor, CodAlmacen, str_cliente_codigo, 
                    str_cliente_cedula, str_cliente_tipo_cedula, str_cliente_nombres, 
                    str_cliente_apellidos, str_cliente_telefono_casa, str_cliente_telefono_celular,
                    str_cliente_telefono_oficina, str_cliente_direccion, str_cliente_email,
                    str_cliente_comentario, str_cliente_status, dte_cliente_ingreso
                ) VALUES (
                    @uid_pais, @uid_estado, @uid_ciudad, @uid_tipocliente,
                    @uid_usuario, @uid_vendedor, @CodAlmacen, @codigo, 
                    @cedula_val, @tipo_cedula, @nombres, 
                    @apellidos, @telefono_casa, @telefono_celular,
                    @telefono_oficina, @direccion, @email,
                    @comentario, @status, GETDATE()
                );
                SELECT SCOPE_IDENTITY() as nuevoId;
            `);

        const nuevoId = insertResult.recordset[0].nuevoId;

        res.status(201).json({
            mensaje: 'Cliente creado exitosamente',
            uid_cliente: nuevoId,
            codigo: codigo
        });

    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

module.exports = router;