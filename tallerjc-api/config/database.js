const sql = require('mssql');
const empresas = require('./empresas.json');
require('dotenv').config();

// Un pool de conexiones por empresa. Se guarda la PROMESA del pool
// para evitar que dos peticiones simultáneas creen pools duplicados.
const pools = new Map();

function getEmpresaConfig(cod) {
    const e = empresas[cod];
    if (!e) {
        const err = new Error(`Empresa '${cod}' no está configurada`);
        err.status = 400;
        throw err;
    }
    return e;
}

function crearPool(cod) {
    const e = getEmpresaConfig(cod);
    const pool = new sql.ConnectionPool({
        server: e.server,
        port: e.port || 1433,
        database: e.database,
        user: e.user,
        password: e.password,
        options: {
            encrypt: false,
            trustServerCertificate: true
        },
        pool: { max: 5, min: 0, idleTimeoutMillis: 30000 },
        connectionTimeout: 8000,
        requestTimeout: 15000
    });

    pool.on('error', err => {
        console.error(`[${cod}] Error de pool:`, err.message);
        pools.delete(cod);
    });

    return pool.connect().then(p => {
        console.log(`Conectado a SQL Server - ${e.nombre} (${cod}) -> ${e.server}:${e.port || 1433}/${e.database}`);
        return p;
    });
}

async function getConnection(codEmpresa) {
    if (!codEmpresa) {
        const err = new Error('Código de empresa requerido para conectar a la base de datos');
        err.status = 500;
        throw err;
    }
    const cod = String(codEmpresa).trim();

    if (!pools.has(cod)) {
        pools.set(cod, crearPool(cod));
    }

    try {
        return await pools.get(cod);
    } catch (error) {
        // Si la conexión falló, se elimina para que el próximo intento reintente
        pools.delete(cod);
        throw error;
    }
}

// Lista pública de empresas (sin credenciales) para el selector del login
function listaEmpresas() {
    return Object.entries(empresas).map(([codigo, e]) => ({
        codigo,
        nombre: e.nombre
    }));
}

module.exports = { getConnection, listaEmpresas, sql };
