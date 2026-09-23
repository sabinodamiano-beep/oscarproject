-- =====================================================================
--  002_tbl_app_idempotencia_cobros.sql
--  Tabla auxiliar de la app movil: llave de idempotencia de POST /cobros.
--  Se ejecuta UNA vez por empresa (tenant), sobre su base LICORES_DB.
--  No toca ninguna tabla de GYFSOFT. InvenSoft no la usa ni la ve.
--  Compatible con SQL Server 2008 R2 en adelante. Idempotente: se puede
--  volver a correr sin efecto (p. ej. tras un restore de la base).
--
--  Ejecutar con:
--  sqlcmd -S localhost -E -d LICORES_DB -i 002_tbl_app_idempotencia_cobros.sql
-- =====================================================================

IF OBJECT_ID('dbo.tbl_app_idempotencia_cobros', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.tbl_app_idempotencia_cobros (
        client_uuid   nvarchar(36) NOT NULL,           -- UUID v4 generado por el telefono
        numpago       nvarchar(7)  NOT NULL,           -- correlativo asignado (serie 9000001+)
        uid_vendedor  nvarchar(10) NOT NULL,
        monto         money        NOT NULL DEFAULT 0, -- para responder igual en un replay
        fecreg        datetime     NOT NULL DEFAULT GETDATE(),
        CONSTRAINT PK_tbl_app_idempotencia_cobros PRIMARY KEY CLUSTERED (client_uuid)
    );
    PRINT 'tbl_app_idempotencia_cobros creada';
END
ELSE
    PRINT 'tbl_app_idempotencia_cobros ya existe';
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_tbl_app_idempotencia_cobros_pago')
    CREATE NONCLUSTERED INDEX IX_tbl_app_idempotencia_cobros_pago
        ON dbo.tbl_app_idempotencia_cobros (numpago);
GO

-- Verificacion
SELECT name, create_date FROM sys.tables WHERE name = 'tbl_app_idempotencia_cobros';
GO
