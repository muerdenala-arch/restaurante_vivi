# 🍗 Pollos Vivi — POS

POS táctil y ligero, construido para operar rápido en pantallas táctiles (tablet / kiosko).

## Stack

- **React 18 + Vite + TypeScript** — build ligero, HMR instantáneo, sin overhead de SSR (no se necesita para un POS de tienda física).
- **Tailwind CSS** — design tokens de la paleta de marca en `tailwind.config.ts`.
- **Framer Motion** — transiciones de página, stagger de catálogo, modales, carrito animado, feedback táctil (`whileTap`).
- **Lucide React** — iconografía SVG (nunca emoji como ícono funcional).
- **Zustand + persist** — estado global (auth, catálogo, carrito, caja, ventas), cacheado en `localStorage` y sincronizado en segundo plano contra el backend.
- **react-router-dom** — rutas protegidas por rol.
- **Vercel Functions + Neon (Postgres)** — API y base de datos central (ver `api/` y `schema.sql`); todos los dispositivos comparten la misma fuente de verdad.
- **Cloudinary** — almacenamiento de imágenes (comprobantes de pago QR, fotos de QR de cobro).

## Dirección visual (UI/UX Pro Max)

- **Paleta de marca**: naranja (`primary`, `#F1710A`) + verde (`secondary`, `#1E9E5A`) + rosa (`accent`, `#EC4899`) sobre fondo crema cálido (`cream`). Contraste verificado para texto sobre fondo/tarjetas.
- **Tipografía**: `Poppins` (display, botones, precios) + `Nunito Sans` (texto de UI) — geométrica, redondeada y muy legible a distancia táctil.
- **Touch targets**: mínimo 48px de alto (`min-h-touch`), 64px en teclados numéricos (`min-h-touch-lg`), spacing ≥ 8px entre elementos interactivos.
- **Motion**: entradas con stagger + spring, salidas más rápidas que las entradas, `prefers-reduced-motion` respetado globalmente.

## Roles

| Rol | Acceso |
|---|---|
| **Administrador** (PIN demo `1234`) | Catálogo, Inventario, Personal, Configuración QR, Sucursales, Auditoría de cajas, Reportes de venta |
| **Cajero** (PIN demo `1111` / `2222`) | Venta rápida táctil (POS), apertura y cierre de caja |

El login es por selección de usuario + PIN de 4 dígitos (pensado para tablet). El rol determina las rutas accesibles (`src/router/RequireAuth.tsx`).

## Funcionalidades clave

- **Catálogo con modificadores**: agregados/toppings (papas extra, salsas, queso extra, etc.) — precio unitario recalculado en vivo (`src/components/pos/ModifierModal.tsx`).
- **Checkout dual**:
  - *Efectivo*: registro rápido del monto cobrado.
  - *QR*: muestra el QR de cobro configurado por el administrador para la sucursal, con foto del comprobante de transferencia adjunta.
- **Comprobante/ticket** con detalle de ítems, modificadores y método de pago; se imprime automáticamente al confirmar el cobro (`src/components/receipt/Ticket.tsx`).
- **Apertura/cierre de caja** con cálculo de efectivo esperado vs. contado y diferencia (sobrante/faltante).
- **Auditoría de cajas** (admin): historial de sesiones con diferencias resaltadas.
- **Inventario básico**: stock por producto y por topping, por sucursal, con alertas de stock bajo.
- **Reportes de venta**: total vendido, ticket promedio, productos más vendidos, desglose por método de pago y por sucursal.

## Empezar

```bash
npm install
cp .env.example .env.local   # completá DATABASE_URL (Neon) y las variables de Cloudinary
npm run dev:full             # vite + funciones de /api vía `vercel dev`
```

Corré `schema.sql` una vez contra tu base de Neon antes del primer arranque — crea las
tablas y siembra el catálogo inicial de Pollos Vivi (es seguro volver a correrlo).

## Estructura

```
src/
  components/
    ui/        # Button, Card, Modal, Badge, Input, NumericKeypad
    layout/    # CashierShell (kiosko), AdminShell (sidebar)
    pos/       # ProductGrid, ModifierModal, CartPanel, CheckoutModal
    admin/     # ProductRow, ProductFormModal
    receipt/   # Ticket
  pages/       # LoginPage, POSPage, CashOpenPage, CashClosePage, admin/*
  store/       # zustand: auth, catalog, cart, register, sales (sincronizados con /api)
  data/seed.ts # catálogo y usuarios semilla (debe coincidir con schema.sql)
  lib/         # utils (cn, formatCurrency), motion (variants Framer Motion)
  types/       # modelo de dominio
  config/app.ts# nombre de tienda, moneda, locale
api/           # Vercel Functions — CRUD contra Neon
```

## Adaptar a otro país/moneda

Edita `src/config/app.ts` (`locale`, `currency`, `currencySymbol`) — todo el formateo de precios pasa por `formatCurrency()` en `src/lib/utils.ts`.
