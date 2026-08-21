-- ============================================================================
-- Pollos Vivi POS — reset "0 km" para entrega a producción
-- ============================================================================
-- Purga TODO el dato transaccional y de catálogo de prueba, dejando la base
-- lista para que el cliente cargue su catálogo real desde el panel Admin.
--
-- SE BORRA POR COMPLETO:
--   - sales            (ventas / tickets)
--   - register_sessions (aperturas/cierres de caja)
--   - qr_codes         (QR de cobro — eran de prueba, el cliente sube el real)
--   - products         (catálogo completo: categorías, tamaños y agregados
--                        asignados viven DENTRO de cada producto, así que
--                        vaciar products ya deja categorías/tamaños en 0)
--   - toppings         (agregados/extras y su stock)
--   - ticket_number_seq se reinicia en 1 → el próximo ticket real es el #1
--
-- SE CONSERVA INTACTO (a propósito, no se toca):
--   - staff    (usuarios admin/cajero y sus PIN — para poder iniciar sesión)
--   - branches (sucursales configuradas)
--
-- Es seguro de re-ejecutar (TRUNCATE de una tabla vacía no falla), pero NO es
-- reversible: no hay backup automático acá. Antes de correrlo se hizo un
-- export puntual a JSON (ver reset-produccion-backup.mjs) por si hiciera
-- falta consultar algo de memoria después.
-- ============================================================================

BEGIN;

-- Una sola sentencia con las 5 tablas juntas: evita el error de Postgres por
-- la FK sales.register_session_id -> register_sessions.id (TRUNCATE exige
-- que ambos lados de una referencia se vacíen en el mismo statement o con
-- CASCADE — acá no hace falta CASCADE porque ya están las dos en la lista).
TRUNCATE TABLE sales, register_sessions, qr_codes, products, toppings
  RESTART IDENTITY;

-- El contador de ticket_number es una sequence manual (no una IDENTITY
-- column), así que RESTART IDENTITY de arriba no la toca — hay que
-- reiniciarla a mano para que el primer pedido real sea el Ticket #1.
ALTER SEQUENCE ticket_number_seq RESTART WITH 1;

COMMIT;

-- ── Verificación rápida post-purga ──────────────────────────────────────
SELECT 'sales' AS tabla, count(*) AS filas FROM sales
UNION ALL SELECT 'register_sessions', count(*) FROM register_sessions
UNION ALL SELECT 'qr_codes', count(*) FROM qr_codes
UNION ALL SELECT 'products', count(*) FROM products
UNION ALL SELECT 'toppings', count(*) FROM toppings
UNION ALL SELECT 'staff (se conserva)', count(*) FROM staff
UNION ALL SELECT 'branches (se conserva)', count(*) FROM branches;
