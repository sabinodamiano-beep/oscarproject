-- =====================================================================
--  001_tbl_app_idempotencia.sql
--  Tabla auxiliar de la app movil: llave de idempotencia de POST /pedidos.
--  Se ejecuta UNA vez por empresa (tenant), sobre su base LICORES_DB.
--  No toca ninguna tabla de GYFSOFT. InvenSoft no la usa ni la ve.
--  Compatible con SQL Server 2008 R2 en adelante. Idempotente: se puede
--  volver a correr sin efecto (p. ej. tras un restore de la base).
-- =====================================================================

IF OBJECT_ID('dbo.tbl_app_idempotencia', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.tbl_app_idempotencia (
        client_uuid   nvarchar(36) NOT NULL,           -- UUID v4 generado por el telefono
        uid_pedido    nvarchar(7)  NOT NULL,           -- correlativo asignado (serie 9000001+)
        uid_vendedor  nvarchar(10) NOT NULL,
        total         money        NOT NULL DEFAULT 0, -- para responder igual en un replay
        total_items   int          NOT NULL DEFAULT 0,
        fecreg        datetime     NOT NULL DEFAULT GETDATE(),
        CONSTRAINT PK_tbl_app_idempotencia PRIMARY KEY CLUSTERED (client_uuid)
    );
    PRINT 'tbl_app_idempotencia creada';
END
ELSE
    PRINT 'tbl_app_idempotencia ya existe';
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_tbl_app_idempotencia_pedido')
    CREATE NONCLUSTERED INDEX IX_tbl_app_idempotencia_pedido
        ON dbo.tbl_app_idempotencia (uid_pedido);
GO

-- Verificacion
SELECT name, create_date FROM sys.tables WHERE name = 'tbl_app_idempotencia';
GO
