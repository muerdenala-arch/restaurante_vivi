-- ============================================================================
-- Pollos Vivi POS — esquema de base de datos (Neon / PostgreSQL)
-- ============================================================================
-- Esta es la fuente de verdad central que comparten todos los dispositivos
-- (PCs, celulares) del punto de venta.
--
-- Diseño: las estructuras anidadas del dominio (tallas de un producto, stock
-- por sucursal, ítems de una venta, datos del pago) se guardan como JSONB en
-- vez de normalizarse en más tablas — reflejan 1:1 los tipos de TypeScript en
-- src/types/index.ts, así que el resto de la app no cambia de forma.
--
-- Es seguro volver a correr este archivo completo: todo usa
-- IF NOT EXISTS / ON CONFLICT DO NOTHING, así que no duplica ni borra datos
-- que ya hayas creado usando la app.
-- ============================================================================

-- ── Sucursales ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS branches (
  id         text PRIMARY KEY,
  name       text NOT NULL,
  address    text NOT NULL DEFAULT '',
  phone      text NOT NULL DEFAULT '',
  active     boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- ── Personal / cajeros ───────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS staff (
  id          text PRIMARY KEY,
  name        text NOT NULL,
  pin         text NOT NULL UNIQUE,
  role        text NOT NULL CHECK (role IN ('admin', 'cajero')),
  color       text NOT NULL DEFAULT 'bg-primary-500',
  status      text NOT NULL DEFAULT 'activo' CHECK (status IN ('activo', 'bloqueado')),
  protected   boolean NOT NULL DEFAULT false,
  -- Array de ids de sucursal, ej. ["central", "norte"]
  branch_ids  jsonb NOT NULL DEFAULT '[]',
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

-- ── Toppings (agregados) ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS toppings (
  id                  text PRIMARY KEY,
  name                text NOT NULL,
  price_extra         numeric(10, 2) NOT NULL DEFAULT 0,
  -- { [branchId]: cantidad }
  stock_by_branch     jsonb NOT NULL DEFAULT '{}',
  low_stock_threshold integer NOT NULL DEFAULT 0,
  updated_at          timestamptz NOT NULL DEFAULT now()
);

-- ── Catálogo de productos ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS products (
  id                   text PRIMARY KEY,
  name                 text NOT NULL,
  category             text NOT NULL,
  description          text NOT NULL DEFAULT '',
  base_price           numeric(10, 2) NOT NULL DEFAULT 0,
  gradient             text NOT NULL DEFAULT '',
  emoji                text NOT NULL DEFAULT '',
  -- [{ id, label, ounces, priceDelta }]
  sizes                jsonb NOT NULL DEFAULT '[]',
  -- ["agua", "leche", ...] — sin uso en el catálogo de pollería, se deja vacío
  base_liquida_options jsonb NOT NULL DEFAULT '[]',
  allow_sugar_level    boolean NOT NULL DEFAULT true,
  -- ["papas-extra", "salsa-aji", ...]
  topping_ids          jsonb NOT NULL DEFAULT '[]',
  active               boolean NOT NULL DEFAULT true,
  -- { [branchId]: cantidad }
  stock_by_branch      jsonb NOT NULL DEFAULT '{}',
  low_stock_threshold  integer NOT NULL DEFAULT 0,
  unit                 text NOT NULL DEFAULT 'unidades',
  updated_at           timestamptz NOT NULL DEFAULT now()
);

-- ── Códigos QR de cobro (imagen sube a Cloudinary, acá se guarda la URL) ──
CREATE TABLE IF NOT EXISTS qr_codes (
  id             text PRIMARY KEY,
  alias          text NOT NULL,
  bank_or_holder text NOT NULL DEFAULT '',
  image_url      text NOT NULL,
  active         boolean NOT NULL DEFAULT true,
  branch_id      text NOT NULL REFERENCES branches (id),
  created_at     timestamptz NOT NULL DEFAULT now()
);

-- ── Aperturas / cierres de caja ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS register_sessions (
  id                     text PRIMARY KEY,
  cashier_id             text NOT NULL,
  cashier_name           text NOT NULL,
  branch_id              text NOT NULL REFERENCES branches (id),
  opened_at              timestamptz NOT NULL DEFAULT now(),
  closed_at              timestamptz,
  opening_amount         numeric(10, 2) NOT NULL DEFAULT 0,
  closing_amount_counted numeric(10, 2),
  expected_amount        numeric(10, 2),
  difference             numeric(10, 2),
  sales_total            numeric(10, 2),
  sales_count            integer,
  cash_sales_total       numeric(10, 2),
  qr_sales_total         numeric(10, 2),
  status                 text NOT NULL DEFAULT 'abierta' CHECK (status IN ('abierta', 'cerrada')),
  notes                  text
);

-- Número de ticket correlativo y atómico entre todos los dispositivos.
CREATE SEQUENCE IF NOT EXISTS ticket_number_seq START WITH 1001;

-- ── Ventas ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS sales (
  id                  text PRIMARY KEY,
  ticket_number       integer NOT NULL DEFAULT nextval('ticket_number_seq'),
  -- [{ lineId, product, modifiers, quantity, unitPrice, lineTotal, notes }]
  items               jsonb NOT NULL,
  subtotal            numeric(10, 2) NOT NULL,
  total               numeric(10, 2) NOT NULL,
  -- { method, amount, receiptImage } — receiptImage es la URL de Cloudinary
  payment             jsonb NOT NULL,
  cashier_id          text NOT NULL,
  cashier_name        text NOT NULL,
  register_session_id text NOT NULL REFERENCES register_sessions (id),
  branch_id           text NOT NULL REFERENCES branches (id),
  created_at          timestamptz NOT NULL DEFAULT now()
);

-- ── Índices para las consultas más frecuentes del panel admin ──────────────
CREATE INDEX IF NOT EXISTS idx_sales_branch ON sales (branch_id);
CREATE INDEX IF NOT EXISTS idx_sales_session ON sales (register_session_id);
CREATE INDEX IF NOT EXISTS idx_sales_created_at ON sales (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_register_sessions_branch ON register_sessions (branch_id);
CREATE INDEX IF NOT EXISTS idx_register_sessions_status ON register_sessions (status);
-- Respalda el `order by opened_at desc limit 500` de /api/register-sessions — sin esto
-- Postgres tiene que ordenar la tabla completa en cada poll de 6s a medida que crece.
CREATE INDEX IF NOT EXISTS idx_register_sessions_opened_at ON register_sessions (opened_at DESC);
CREATE INDEX IF NOT EXISTS idx_qr_codes_branch ON qr_codes (branch_id);

-- ============================================================================
-- Datos semilla — mismos valores que src/data/seed.ts, para que el primer
-- arranque contra Neon se vea igual que la demo local. No pisa nada si ya
-- existen filas con esos ids (ON CONFLICT DO NOTHING).
-- ============================================================================

INSERT INTO branches (id, name, address, phone, active) VALUES
  ('central', 'Sucursal Central', 'Av. Principal 123, Centro', '700-00001', true),
  ('norte',   'Sucursal Norte',   'Av. Norte 456, Zona Norte', '700-00002', true),
  ('sur',     'Sucursal Sur',     'Av. Sur 789, Zona Sur',     '700-00003', true)
ON CONFLICT (id) DO NOTHING;

INSERT INTO staff (id, name, pin, role, color, status, protected, branch_ids, created_at) VALUES
  ('u-admin',   'Valeria Ríos', '1234', 'admin',  'bg-accent-500',    'activo', true,  '["central","norte","sur"]', '2026-01-05T09:00:00.000Z'),
  ('u-cajero1', 'Diego Mamani', '1111', 'cajero', 'bg-primary-500',   'activo', false, '["central"]',              '2026-02-12T09:00:00.000Z'),
  ('u-cajero2', 'Ana Quispe',   '2222', 'cajero', 'bg-secondary-500', 'activo', false, '["central","norte","sur"]', '2026-03-20T09:00:00.000Z')
ON CONFLICT (id) DO NOTHING;

INSERT INTO toppings (id, name, price_extra, stock_by_branch, low_stock_threshold) VALUES
  ('papas-extra',    'Papas fritas extra',      8,   '{"central":40,"norte":24,"sur":14}', 8),
  ('salsa-aji',       'Salsa de ají',            2,   '{"central":60,"norte":36,"sur":21}', 10),
  ('salsa-golf',      'Salsa golf',              2,   '{"central":60,"norte":36,"sur":21}', 10),
  ('queso-extra',     'Queso extra',             5,   '{"central":30,"norte":18,"sur":11}', 8),
  ('ensalada-extra',  'Ensalada extra',          6,   '{"central":25,"norte":15,"sur":9}',  6),
  ('pan',             'Pan de acompañamiento',   3,   '{"central":35,"norte":21,"sur":12}', 8)
ON CONFLICT (id) DO NOTHING;

INSERT INTO products (
  id, name, category, description, base_price, gradient, emoji, sizes,
  base_liquida_options, allow_sugar_level, topping_ids, active, stock_by_branch,
  low_stock_threshold, unit
) VALUES
  ('p-combo-familiar-4', 'Combo Familiar x4', 'Combos Familiares', 'Pollo entero + papas familiares + ensalada + gaseosa 1.5L.', 95,
   'from-red-400 to-orange-500', '🍗',
   '[{"id":"unico","label":"Único","ounces":0,"priceDelta":0}]',
   '[]', false, '["papas-extra","salsa-aji","salsa-golf","queso-extra"]', true,
   '{"central":12,"norte":7,"sur":4}', 4, 'combos'),

  ('p-combo-pareja-2', 'Combo Pareja x2', 'Combos Familiares', 'Medio pollo + papas + gaseosa 1L.', 55,
   'from-orange-400 to-amber-500', '🍗',
   '[{"id":"unico","label":"Único","ounces":0,"priceDelta":0}]',
   '[]', false, '["papas-extra","salsa-aji","salsa-golf"]', true,
   '{"central":18,"norte":11,"sur":6}', 6, 'combos'),

  ('p-cuarto-papas', 'Cuarto de Pollo + Papas', 'Cuartos de Pollo', 'Cuarto de pollo broaster con papas fritas.', 28,
   'from-amber-400 to-orange-600', '🍗',
   '[{"id":"unico","label":"Único","ounces":0,"priceDelta":0}]',
   '[]', false, '["salsa-aji","salsa-golf","queso-extra","pan"]', true,
   '{"central":35,"norte":21,"sur":12}', 10, 'porciones'),

  ('p-cuarto-arroz', 'Cuarto de Pollo + Arroz Chaufa', 'Cuartos de Pollo', 'Cuarto de pollo broaster con arroz chaufa.', 28,
   'from-orange-400 to-amber-500', '🍗',
   '[{"id":"unico","label":"Único","ounces":0,"priceDelta":0}]',
   '[]', false, '["salsa-aji","salsa-golf","pan"]', true,
   '{"central":28,"norte":17,"sur":10}', 10, 'porciones'),

  ('p-medio-papas', 'Medio Pollo + Papas', 'Medios', 'Medio pollo broaster con papas fritas familiares.', 48,
   'from-red-400 to-orange-500', '🍗',
   '[{"id":"unico","label":"Único","ounces":0,"priceDelta":0}]',
   '[]', false, '["papas-extra","salsa-aji","salsa-golf","queso-extra"]', true,
   '{"central":20,"norte":12,"sur":7}', 6, 'porciones'),

  ('p-medio-ensalada', 'Medio Pollo + Ensalada', 'Medios', 'Medio pollo broaster con ensalada fresca.', 48,
   'from-amber-400 to-orange-600', '🍗',
   '[{"id":"unico","label":"Único","ounces":0,"priceDelta":0}]',
   '[]', false, '["ensalada-extra","salsa-aji","queso-extra"]', true,
   '{"central":16,"norte":10,"sur":6}', 6, 'porciones'),

  ('p-pollo-entero', 'Pollo Entero a la Broaster', 'Enteros', 'Pollo entero broaster, crocante y jugoso.', 85,
   'from-orange-500 to-red-600', '🍗',
   '[{"id":"unico","label":"Único","ounces":0,"priceDelta":0}]',
   '[]', false, '["salsa-aji","salsa-golf","queso-extra","pan"]', true,
   '{"central":10,"norte":6,"sur":4}', 4, 'unidades'),

  ('p-pollo-entero-papas', 'Pollo Entero + Papas Grandes', 'Enteros', 'Pollo entero broaster con papas fritas grandes.', 98,
   'from-red-400 to-orange-500', '🍗',
   '[{"id":"unico","label":"Único","ounces":0,"priceDelta":0}]',
   '[]', false, '["papas-extra","salsa-aji","salsa-golf","queso-extra","pan"]', true,
   '{"central":8,"norte":5,"sur":3}', 4, 'unidades'),

  ('p-presa-pechuga', 'Presa - Pechuga', 'Presas', 'Presa individual de pechuga broaster.', 14,
   'from-yellow-300 to-orange-400', '🍗',
   '[{"id":"unico","label":"Único","ounces":0,"priceDelta":0}]',
   '[]', false, '["salsa-aji","salsa-golf"]', true,
   '{"central":40,"norte":24,"sur":14}', 12, 'unidades'),

  ('p-presa-pierna', 'Presa - Pierna', 'Presas', 'Presa individual de pierna broaster.', 12,
   'from-amber-400 to-orange-600', '🍗',
   '[{"id":"unico","label":"Único","ounces":0,"priceDelta":0}]',
   '[]', false, '["salsa-aji","salsa-golf"]', true,
   '{"central":45,"norte":27,"sur":16}', 12, 'unidades'),

  ('p-presa-ala', 'Presa - Ala', 'Presas', 'Presa individual de ala broaster.', 10,
   'from-orange-400 to-amber-500', '🍗',
   '[{"id":"unico","label":"Único","ounces":0,"priceDelta":0}]',
   '[]', false, '["salsa-aji","salsa-golf"]', true,
   '{"central":50,"norte":30,"sur":18}', 15, 'unidades'),

  ('p-papas-personal', 'Papas Fritas Personal', 'Papas Fritas', 'Porción personal de papas fritas crocantes.', 12,
   'from-yellow-300 to-orange-400', '🍟',
   '[{"id":"unico","label":"Único","ounces":0,"priceDelta":0}]',
   '[]', false, '["salsa-aji","salsa-golf","queso-extra"]', true,
   '{"central":30,"norte":18,"sur":11}', 10, 'porciones'),

  ('p-papas-familiar', 'Papas Fritas Familiar', 'Papas Fritas', 'Porción familiar de papas fritas crocantes.', 22,
   'from-amber-400 to-orange-600', '🍟',
   '[{"id":"unico","label":"Único","ounces":0,"priceDelta":0}]',
   '[]', false, '["salsa-aji","salsa-golf","queso-extra"]', true,
   '{"central":18,"norte":11,"sur":6}', 6, 'porciones'),

  ('p-arroz-chaufa', 'Arroz Chaufa', 'Arroz Chaufa/Plátano', 'Arroz chaufa salteado con vegetales.', 15,
   'from-emerald-400 to-teal-500', '🍚',
   '[{"id":"unico","label":"Único","ounces":0,"priceDelta":0}]',
   '[]', false, '["salsa-aji"]', true,
   '{"central":22,"norte":13,"sur":8}', 8, 'porciones'),

  ('p-platano-frito', 'Plátano Frito', 'Arroz Chaufa/Plátano', 'Plátano maduro frito en tajadas.', 10,
   'from-yellow-300 to-orange-400', '🍌',
   '[{"id":"unico","label":"Único","ounces":0,"priceDelta":0}]',
   '[]', false, '[]', true,
   '{"central":20,"norte":12,"sur":7}', 8, 'porciones'),

  ('p-ensalada-clasica', 'Ensalada Clásica', 'Ensaladas', 'Lechuga, tomate, cebolla y zanahoria.', 12,
   'from-lime-400 to-emerald-500', '🥗',
   '[{"id":"unico","label":"Único","ounces":0,"priceDelta":0}]',
   '[]', false, '["queso-extra"]', true,
   '{"central":20,"norte":12,"sur":7}', 8, 'porciones'),

  ('p-ensalada-cesar', 'Ensalada César', 'Ensaladas', 'Lechuga, pollo, crutones, parmesano y aderezo césar.', 16,
   'from-emerald-400 to-teal-500', '🥗',
   '[{"id":"unico","label":"Único","ounces":0,"priceDelta":0}]',
   '[]', false, '["queso-extra"]', true,
   '{"central":14,"norte":8,"sur":5}', 6, 'porciones'),

  ('p-gaseosa-personal', 'Gaseosa Personal 350ml', 'Refrescos y Gaseosas', 'Gaseosa en lata o botella personal.', 7,
   'from-sky-400 to-blue-500', '🥤',
   '[{"id":"unico","label":"Único","ounces":0,"priceDelta":0}]',
   '[]', false, '[]', true,
   '{"central":60,"norte":36,"sur":21}', 15, 'unidades'),

  ('p-gaseosa-litro', 'Gaseosa 1.5L', 'Refrescos y Gaseosas', 'Gaseosa familiar de 1.5 litros.', 15,
   'from-sky-400 to-blue-500', '🥤',
   '[{"id":"unico","label":"Único","ounces":0,"priceDelta":0}]',
   '[]', false, '[]', true,
   '{"central":30,"norte":18,"sur":11}', 10, 'unidades'),

  ('p-agua-mineral', 'Agua Mineral', 'Refrescos y Gaseosas', 'Agua mineral con o sin gas, 600ml.', 6,
   'from-sky-400 to-blue-500', '💧',
   '[{"id":"unico","label":"Único","ounces":0,"priceDelta":0}]',
   '[]', false, '[]', true,
   '{"central":40,"norte":24,"sur":14}', 12, 'unidades')
ON CONFLICT (id) DO NOTHING;
