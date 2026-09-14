# Sesión 0 — Despliegue y pruebas

**Fecha:** 30 de agosto de 2026
**Cambios:** `routes/clientes.js`, `routes/productos.js`, `routes/pedidos.js`, `sql/001_tbl_app_idempotencia.sql`.
**Retrocompatible:** la app 1.1.0 instalada sigue funcionando sin cambios.

Decisiones aplicadas: D1 = tabla auxiliar `tbl_app_idempotencia` · D2 = sin clientes offline · D3 = **caché válida máximo 1 día** (aplica en Sesión 1: el objetivo es cubrir pérdidas de señal, no jornadas enteras sin sincronizar).

---

## 1. Copiar archivos a `DESKTOP-MJILHOV`

Desde el Mac, los cuatro archivos van a `C:\licores-api\` respetando carpetas (`routes\` y `sql\`). Antes, respaldo en la PC (un comando por vez):

```powershell
Copy-Item C:\licores-api\routes\*.js C:\licores-api\routes\bak_$(Get-Date -Format yyyyMMdd)\ -Force
```

(si la carpeta no existe: `New-Item -ItemType Directory C:\licores-api\routes\bak_$(Get-Date -Format yyyyMMdd)` primero)

## 2. Crear la tabla auxiliar en cada tenant

Tenant `001` (local):
```powershell
sqlcmd -S localhost,1433 -U sa -P 000000 -d LICORES_DB -i C:\licores-api\sql\001_tbl_app_idempotencia.sql
```

Tenant `002` (SERVIDOR-LICSLE por la tailnet):
```powershell
sqlcmd -S servidor-licsle.tail048866.ts.net,1533 -U sa -P 000000 -d LICORES_DB -i C:\licores-api\sql\001_tbl_app_idempotencia.sql
```

Salida esperada en ambos: `tbl_app_idempotencia creada` y una fila con `name / create_date`.

> **OJO — corte de InvenSoft:** el día del corte se vuelve a restaurar `LICORES_DB` en `GYFSOFT` desde el backup del SQL 2000, y **esa restauración borra la tabla**. Hay que volver a correr este script en `002` inmediatamente después del restore. Agregado al runbook del corte como paso 1-bis. El script es idempotente, correrlo dos veces no hace daño.

## 3. Reiniciar la API

```powershell
pm2.cmd restart licores-api
```
```powershell
pm2.cmd logs licores-api --lines 20
```

---

## 4. Pruebas (desde el Mac, contra el Funnel)

Variables:
```bash
API=https://desktop-mjilhov.tail048866.ts.net/api
```

### 4.1 Login tenant 001
```bash
TOKEN=$(curl -s -X POST $API/login -H "Content-Type: application/json" \
  -d '{"empresa":"001","cedula":"2","password":"2"}' | python3 -c "import sys,json;print(json.load(sys.stdin)['token'])")
echo $TOKEN | cut -c1-30
```

### 4.2 Catálogos completos (deben superar los 50 / 100 de antes)
```bash
curl -s "$API/clientes?todos=1" -H "Authorization: Bearer $TOKEN" | python3 -c "import sys,json;print('clientes:',len(json.load(sys.stdin)))"
```
```bash
curl -s "$API/productos?todos=1" -H "Authorization: Bearer $TOKEN" | python3 -c "import sys,json;print('productos:',len(json.load(sys.stdin)))"
```
Esperado en `001`: ~1054 clientes, ~595 productos. Y sin `todos=1` siguen saliendo 50 / 100:
```bash
curl -s "$API/clientes" -H "Authorization: Bearer $TOKEN" | python3 -c "import sys,json;print('sin todos:',len(json.load(sys.stdin)))"
```

### 4.3 Idempotencia — la prueba que importa
Un UUID, el mismo pedido enviado **dos veces**:
```bash
UUID=$(uuidgen | tr 'A-Z' 'a-z'); echo $UUID
```
Primer envío (esperado `201`, `"mensaje":"Pedido creado"`, anota el `uid_pedido`):
```bash
curl -s -w "\nHTTP %{http_code}\n" -X POST $API/pedidos -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "{\"uid_cliente\":1,\"observaciones\":\"PRUEBA IDEMPOTENCIA\",\"client_uuid\":\"$UUID\",\"items\":[{\"coditems\":\"CODIGO_REAL\",\"cajas\":1,\"botellas\":0}]}"
```
Segundo envío, idéntico (esperado `200`, `"replay":true`, **mismo** `uid_pedido`):
```bash
curl -s -w "\nHTTP %{http_code}\n" -X POST $API/pedidos -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "{\"uid_cliente\":1,\"observaciones\":\"PRUEBA IDEMPOTENCIA\",\"client_uuid\":\"$UUID\",\"items\":[{\"coditems\":\"CODIGO_REAL\",\"cajas\":1,\"botellas\":0}]}"
```
Reemplaza `CODIGO_REAL` por un `coditems` activo (tómalo del 4.2) y `uid_cliente` por uno existente.

Verificación en la base (PowerShell en la PC), debe dar **una sola** fila en cada consulta:
```powershell
sqlcmd -S localhost,1433 -U sa -P 000000 -d LICORES_DB -Q "SELECT uid_pedido, total, fecreg FROM tbl_app_idempotencia"
```
```powershell
sqlcmd -S localhost,1433 -U sa -P 000000 -d LICORES_DB -Q "SELECT uid_pedido, observaciones, total FROM tbl_mpedidos WHERE observaciones = 'PRUEBA IDEMPOTENCIA'"
```

### 4.4 Sin UUID sigue igual (retrocompatibilidad)
Mismo POST sin `client_uuid` → `201` normal y no escribe en `tbl_app_idempotencia`.

### 4.5 UUID malformado se ignora (no rompe)
`"client_uuid":"hola"` → se trata como si no viniera: `201` normal.

---

## 5. Limpieza tras la prueba
```powershell
sqlcmd -S localhost,1433 -U sa -P 000000 -d LICORES_DB -Q "DELETE FROM tbl_dpedidos WHERE uid_pedido IN (SELECT uid_pedido FROM tbl_mpedidos WHERE observaciones='PRUEBA IDEMPOTENCIA'); DELETE FROM tbl_mpedidos WHERE observaciones='PRUEBA IDEMPOTENCIA'; DELETE FROM tbl_app_idempotencia"
```

---

## Contrato para la app (Sesión 2)

`POST /api/pedidos` body: `{ uid_cliente, observaciones?, items:[{coditems,cajas,botellas}], client_uuid }`

| HTTP | `replay` | Significado para el outbox |
|---|---|---|
| `201` | — | creado ahora → estado `enviado`, guardar `uid_pedido` |
| `200` | `true` | ya existía (reintento tras respuesta perdida) → estado `enviado`, guardar `uid_pedido` |
| `400` / `404` | — | error de negocio (producto inactivo, cliente no existe) → estado `fallido` con `error` |
| `401` | — | token vencido → conservar `pendiente`, pedir login |
| sin respuesta / timeout | — | conservar `pendiente`, reintentar |
