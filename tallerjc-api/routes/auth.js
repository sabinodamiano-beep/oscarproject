const express = require('express');
const jwt = require('jsonwebtoken');
const { getConnection, listaEmpresas, sql } = require('../config/database');

const router = express.Router();

// Lista de empresas disponibles (público, para el selector del login en la app)
router.get('/empresas', (req, res) => {
    res.json(listaEmpresas());
});

// Login multi-tenant
router.post('/login', async (req, res) => {
    try {
        const { empresa, cedula, password } = req.body;

        if (!empresa || !cedula || !password) {
            return res.status(400).json({ error: 'Empresa, cédula y contraseña son obligatorios' });
        }

        const pool = await getConnection(empresa);
        const result = await pool.request()
            .input('cedula', sql.NVarChar, String(cedula))
            .query(`
                SELECT uid_vendedor, str_vendedor_nombre, str_vendedor_apellido,
                       str_vendedor_cedula, str_vendedor_password,
                       status, letra, num_vendedor_comision
                FROM tbl_vendedor
                WHERE str_vendedor_cedula = @cedula OR uid_vendedor = @cedula
            `);

        if (result.recordset.length === 0) {
            return res.status(401).json({ error: 'Vendedor no encontrado' });
        }

        const vendedor = result.recordset[0];

        if (String(vendedor.status).trim() !== '1') {
            return res.status(401).json({ error: 'Vendedor inactivo' });
        }

        // NCHAR trae espacios al final: siempre .trim() antes de comparar
        const passDB = vendedor.str_vendedor_password ? String(vendedor.str_vendedor_password).trim() : '';
        if (passDB === '' || passDB !== String(password)) {
            return res.status(401).json({ error: 'Contraseña incorrecta' });
        }

        const uidVendedor = String(vendedor.uid_vendedor);

        const token = jwt.sign(
            {
                uid_vendedor: uidVendedor,
                nombre: vendedor.str_vendedor_nombre,
                apellido: vendedor.str_vendedor_apellido,
                cedula: vendedor.str_vendedor_cedula,
                empresa: String(empresa).trim()
            },
            process.env.JWT_SECRET,
            { expiresIn: '7d' }
        );

        res.json({
            token,
            empresa: String(empresa).trim(),
            vendedor: {
                uid_vendedor: uidVendedor,
                nombre: vendedor.str_vendedor_nombre,
                apellido: vendedor.str_vendedor_apellido,
                cedula: vendedor.str_vendedor_cedula,
                letra: vendedor.letra,
                comision: vendedor.num_vendedor_comision
            }
        });

    } catch (error) {
        if (error.status === 400) {
            return res.status(400).json({ error: error.message });
        }
        res.status(500).json({ error: error.message });
    }
});

module.exports = router;
