const express = require('express');
const { getConnection, sql } = require('../config/database');
const { verificarToken } = require('../middleware/auth');

const router = express.Router();

router.get('/dashboard', verificarToken, async (req, res) => {
    try {
        const pool = await getConnection(req.empresa);
        const uid_vendedor = String(req.vendedor.uid_vendedor);

        // Pedidos del día (del vendedor logueado)
        const pedidosDia = await pool.request()
            .input('uid_vendedor', sql.NVarChar, uid_vendedor)
            .query(`
                SELECT COUNT(*) as total FROM tbl_mpedidos 
                WHERE CAST(fecha_pedido AS DATE) = CAST(GETDATE() AS DATE)
                AND uid_vendedor = @uid_vendedor AND tipodoc = '0001' AND id_status <> '99'
            `);

        // Pedidos pendientes (del vendedor logueado)
        const pedidosPendientes = await pool.request()
            .input('uid_vendedor', sql.NVarChar, uid_vendedor)
            .query(`
                SELECT COUNT(*) as total FROM tbl_mpedidos 
                WHERE id_status = '00'
                AND uid_vendedor = @uid_vendedor AND tipodoc = '0001'
            `);

        const totalClientes = await pool.request().query(`
            SELECT COUNT(*) as total FROM tbl_clientes
        `);

        const totalProductos = await pool.request().query(`
            SELECT COUNT(*) as total FROM tbl_items WHERE activo = '1'
        `);

        res.json({
            pedidos_dia: pedidosDia.recordset[0].total,
            pedidos_pendientes: pedidosPendientes.recordset[0].total,
            total_clientes: totalClientes.recordset[0].total,
            total_productos: totalProductos.recordset[0].total
        });

    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

module.exports = router;