const jwt = require('jsonwebtoken');
require('dotenv').config();

function verificarToken(req, res, next) {
    const header = req.headers['authorization'];
    if (!header) {
        return res.status(401).json({ error: 'Token no proporcionado' });
    }

    const token = header.split(' ')[1];
    try {
        const decoded = jwt.verify(token, process.env.JWT_SECRET);

        // Tokens emitidos antes del cambio multi-tenant no traen empresa:
        // se fuerza un nuevo login para que el tenant viaje firmado en el token.
        if (!decoded.empresa) {
            return res.status(401).json({ error: 'Sesión antigua, inicie sesión nuevamente' });
        }

        req.vendedor = decoded;
        req.empresa = decoded.empresa;
        next();
    } catch (error) {
        return res.status(401).json({ error: 'Token inválido o expirado' });
    }
}

module.exports = { verificarToken };
