const express = require('express');
const cors = require('cors');
require('dotenv').config();
const { getConnection, listaEmpresas } = require('./config/database');
const authRoutes = require('./routes/auth');
const dashboardRoutes = require('./routes/dashboard');
const clientesRoutes = require('./routes/clientes');
const productosRoutes = require('./routes/productos');
const pedidosRoutes = require('./routes/pedidos');

const app = express();
app.use(cors());
app.use(express.json());

// Rutas
app.use('/api', authRoutes);
app.use('/api', dashboardRoutes);
app.use('/api', clientesRoutes);
app.use('/api', productosRoutes);
app.use('/api', pedidosRoutes);

// Ping sin base de datos: responde aunque los SQL estén caídos.
// Es el endpoint que usará el botón "probar conexión" de la app.
app.get('/api/test', (req, res) => {
    res.json({
        status: 'API Licores funcionando',
        empresas: listaEmpresas().length
    });
});

// Test de conexión a la base de una empresa específica
app.get('/api/test/:empresa', async (req, res) => {
    try {
        const pool = await getConnection(req.params.empresa);
        const result = await pool.request().query('SELECT COUNT(*) as total FROM tbl_vendedor');
        res.json({
            status: 'OK',
            empresa: req.params.empresa,
            vendedores: result.recordset[0].total
        });
    } catch (error) {
        res.status(503).json({
            status: 'SIN CONEXION',
            empresa: req.params.empresa,
            error: error.message
        });
    }
});

const PORT = process.env.API_PORT || 3000;
app.listen(PORT, () => {
    console.log(`API Licores multi-tenant corriendo en puerto ${PORT}`);
});
