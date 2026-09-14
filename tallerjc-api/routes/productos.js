const express = require('express');
const { getConnection, sql } = require('../config/database');
const { verificarToken } = require('../middleware/auth');

const router = express.Router();

// Listar productos con búsqueda
router.get('/productos', verificarToken, async (req, res) => {
    try {
        const { buscar, linea, todos } = req.query;
        const pool = await getConnection(req.empresa);

        // ?todos=1 -> catálogo completo para la caché offline de la app (sin TOP)
        const completo = String(todos) === '1';

        let query = `
            SELECT ${completo ? '' : 'TOP 100'}
                i.coditems, i.desitems, i.existencia, i.ubicacion,
                i.CodBarra, i.activo, i.Status, i.costo,
                i.porcentaje_pvp, i.porcentaje_especial, 
                i.porcentaje_distribuidor, i.porcentaje_mayor, i.porcentaje_oferta,
                i.VentaCaja, i.VentaBotella, i.cantunidad, i.DOLpre,
                i.DOLofe, i.DOLmay, i.DOLdis, i.DOLesp,
                i.Cod_Marca, i.Cod_Linea, i.Cod_Presentacion,
                l.Nombre_Linea, p.Nombre_Presentacion
            FROM tbl_items i
            LEFT JOIN tbl_linea l ON i.Cod_Linea = l.Cod_Linea
            LEFT JOIN tbl_presentacion p ON i.Cod_Presentacion = p.Cod_Presentacion
            WHERE i.activo = '1'
        `;

        if (buscar) {
            query += ` AND (i.desitems LIKE @buscar 
                       OR i.coditems LIKE @buscar 
                       OR i.CodBarra LIKE @buscar)`;
        }
        // Filtro por nombre de línea (tbl_linea tiene duplicados por nombre, por eso se compara el texto)
        if (linea) {
            query += ' AND RTRIM(l.Nombre_Linea) = @linea';
        }

        query += ' ORDER BY i.desitems';

        const request = pool.request();
        if (buscar) {
            request.input('buscar', sql.NVarChar, `%${buscar}%`);
        }
        if (linea) {
            request.input('linea', sql.NVarChar, String(linea).trim());
        }

        const result = await request.query(query);
        res.json(result.recordset);

    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Detalle de un producto
router.get('/productos/:codigo', verificarToken, async (req, res) => {
    try {
        const pool = await getConnection(req.empresa);
        const result = await pool.request()
            .input('codigo', sql.NVarChar, req.params.codigo)
            .query(`
                SELECT i.*, l.Nombre_Linea, p.Nombre_Presentacion
                FROM tbl_items i
                LEFT JOIN tbl_linea l ON i.Cod_Linea = l.Cod_Linea
                LEFT JOIN tbl_presentacion p ON i.Cod_Presentacion = p.Cod_Presentacion
                WHERE i.coditems = @codigo
            `);

        if (result.recordset.length === 0) {
            return res.status(404).json({ error: 'Producto no encontrado' });
        }

        res.json(result.recordset[0]);

    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Listar marcas
router.get('/marcas', verificarToken, async (req, res) => {
    try {
        const pool = await getConnection(req.empresa);
        const result = await pool.request()
            .query('SELECT Cod_Marca, Nombre_Marca FROM tbl_marca WHERE status = 1');

        res.json(result.recordset);

    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Listar líneas
router.get('/lineas', verificarToken, async (req, res) => {
    try {
        const pool = await getConnection(req.empresa);
        const result = await pool.request()
            .query(`SELECT RTRIM(l.Nombre_Linea) AS Nombre_Linea, COUNT(i.coditems) AS productos
                    FROM tbl_linea l
                    JOIN tbl_items i ON i.Cod_Linea = l.Cod_Linea AND i.activo = '1'
                    WHERE l.status = 1
                    GROUP BY RTRIM(l.Nombre_Linea)
                    HAVING COUNT(i.coditems) > 0
                    ORDER BY RTRIM(l.Nombre_Linea)`);

        res.json(result.recordset);

    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Listar presentaciones
router.get('/presentaciones', verificarToken, async (req, res) => {
    try {
        const pool = await getConnection(req.empresa);
        const result = await pool.request()
            .query('SELECT Cod_Presentacion, Nombre_Presentacion FROM tbl_presentacion WHERE status = 1');

        res.json(result.recordset);

    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

module.exports = router;