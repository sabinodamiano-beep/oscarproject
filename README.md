# Fase 2 — Pedidos completos

## API (copiar a `C:\licores-api\routes\` y al Mac)
| Archivo | Cambios |
|---|---|
| `routes/pedidos.js` | `PUT /api/pedidos/:id` (editar pedido en proceso), `GET /api/pedidos?status=&buscar=&desde=&hasta=`, `GET /api/pedidos/:id` ahora incluye datos actuales del producto (`DOLpre`, `cantunidad`, `VentaBotella`, `activo`, línea, presentación), lógica de cálculo unificada en `calcularLineas()`, códigos 403/409 |
| `routes/productos.js` | `GET /api/productos?linea=NOMBRE`, TOP 100, `GET /api/lineas` agrupado por nombre y solo líneas con productos activos |
| `routes/dashboard.js` | Contadores filtran `tipodoc='0001'` y excluyen anulados |

Reiniciar: `pm2.cmd restart licores-api`

## App (copiar `app/lib/` encima de `tallerjc_app/lib/`)
Nuevos / modificados:
- `core/network/api_client.dart` — maneja 403 y 409 con el mensaje del servidor
- `main.dart` — registra `ActualizarPedidoUseCase` y `GetLineasUseCase`
- `features/pedidos/**` — edición de pedidos (carrito en modo edición), filtros por estado y búsqueda en la lista, botón Editar en el detalle
- `features/items/**` — filtro por línea (chips), precio en lugar de stock, sin marca ni litros, detalle con precio por caja / botella

## Pruebas rápidas (PowerShell en la PC de Sabino)
```powershell
$login = Invoke-RestMethod -Uri http://localhost:3000/api/login -Method Post -ContentType "application/json" -Body '{"cedula":"2","password":"2"}'; $h = @{ Authorization = "Bearer $($login.token)" }
# editar el 9000001: cambiar cantidades y agregar un producto
Invoke-RestMethod -Uri http://localhost:3000/api/pedidos/9000001 -Method Put -Headers $h -ContentType "application/json" -Body '{"observaciones":"EDITADO","items":[{"coditems":"5EN1","cajas":5},{"coditems":"ANTISULF","cajas":1}]}'
# filtros
Invoke-RestMethod "http://localhost:3000/api/pedidos?status=00" -Headers $h | Format-Table uid_pedido, status, total
Invoke-RestMethod "http://localhost:3000/api/pedidos?buscar=MULTI" -Headers $h | Format-Table uid_pedido, str_cliente_nombres
# intentar editar uno anulado → 409
Invoke-RestMethod -Uri http://localhost:3000/api/pedidos/9000002 -Method Put -Headers $h -ContentType "application/json" -Body '{"items":[{"coditems":"5EN1","cajas":1}]}'
# líneas y filtro
Invoke-RestMethod http://localhost:3000/api/lineas -Headers $h | Format-Table
```
