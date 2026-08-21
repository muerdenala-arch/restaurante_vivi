import { useEffect, useState } from 'react';
import { Plus, X } from 'lucide-react';
import { Modal } from '@/components/ui/Modal';
import { Input, fieldClasses, fieldLabelClasses } from '@/components/ui/Input';
import { Button } from '@/components/ui/Button';
import { optionActiveClasses, optionInactiveClasses } from '@/lib/optionStyles';
import { useCatalogStore } from '@/store/catalogStore';
import { useBranchStore } from '@/store/branchStore';
import { CATEGORIES } from '@/data/seed';
import type { Product, SizeOption } from '@/types';
import { cn, uid } from '@/lib/utils';

interface ProductFormModalProps {
  product: Product | null;
  open: boolean;
  onClose: () => void;
}

// Temáticos de gastronomía/pollería — nada de frutas ni íconos genéricos de la juguería.
const EMOJI_OPTIONS = ['🍗', '🍖', '🧺', '🍟', '🍚', '🥗', '🥤', '💧', '🌶️', '🧀', '🍌', '🥫'];
// Naranja/rojo/ámbar como base (marca Pollos Vivi), verde para ensaladas/vegetales, azul
// para bebidas/agua y un tono rosa (acento de marca) para redondear la paleta.
const GRADIENT_OPTIONS = [
  'from-orange-400 to-amber-500',
  'from-red-400 to-orange-500',
  'from-amber-400 to-orange-600',
  'from-yellow-300 to-orange-400',
  'from-orange-500 to-red-600',
  'from-lime-400 to-emerald-500',
  'from-emerald-400 to-teal-500',
  'from-sky-400 to-blue-500',
  'from-pink-400 to-rose-500',
];

interface SizeRow {
  id: string;
  label: string;
  price: string;
}

const DEFAULT_SIZES: SizeRow[] = [{ id: 'unico', label: 'Único', price: '10' }];

const emptyForm = {
  name: '',
  category: CATEGORIES[0] ?? 'Combos Familiares',
  description: '',
  sizes: DEFAULT_SIZES,
  stock: '20',
  lowStockThreshold: '8',
  emoji: EMOJI_OPTIONS[0],
  gradient: GRADIENT_OPTIONS[0],
  toppingIds: [] as string[],
};

export function ProductFormModal({ product, open, onClose }: ProductFormModalProps) {
  const toppings = useCatalogStore((s) => s.toppings);
  const upsertProduct = useCatalogStore((s) => s.upsertProduct);
  const createProduct = useCatalogStore((s) => s.createProduct);
  const createTopping = useCatalogStore((s) => s.createTopping);
  const branches = useBranchStore((s) => s.branches);
  const [form, setForm] = useState(emptyForm);
  const [newExtraName, setNewExtraName] = useState('');
  const [newExtraPrice, setNewExtraPrice] = useState('');

  useEffect(() => {
    if (product) {
      setForm({
        name: product.name,
        category: product.category,
        description: product.description,
        // Cada tamaño se edita como precio absoluto (más intuitivo que un delta) — se
        // reconstruye sumando basePrice + priceDelta de cada uno.
        sizes: product.sizes.length
          ? product.sizes.map((s) => ({ id: s.id, label: s.label, price: String(product.basePrice + s.priceDelta) }))
          : DEFAULT_SIZES,
        stock: '0',
        lowStockThreshold: String(product.lowStockThreshold),
        emoji: product.emoji,
        gradient: product.gradient,
        toppingIds: product.toppingIds,
      });
    } else {
      setForm(emptyForm);
    }
    setNewExtraName('');
    setNewExtraPrice('');
  }, [product, open]);

  function addSizeRow() {
    setForm((f) => ({ ...f, sizes: [...f.sizes, { id: uid('size'), label: '', price: f.sizes[0]?.price ?? '10' }] }));
  }

  function updateSizeRow(index: number, patch: Partial<Pick<SizeRow, 'label' | 'price'>>) {
    setForm((f) => ({ ...f, sizes: f.sizes.map((s, i) => (i === index ? { ...s, ...patch } : s)) }));
  }

  function removeSizeRow(index: number) {
    setForm((f) => (f.sizes.length <= 1 ? f : { ...f, sizes: f.sizes.filter((_, i) => i !== index) }));
  }

  function toggleTopping(id: string) {
    setForm((f) => ({
      ...f,
      toppingIds: f.toppingIds.includes(id) ? f.toppingIds.filter((t) => t !== id) : [...f.toppingIds, id],
    }));
  }

  function handleCreateExtra() {
    if (!newExtraName.trim()) return;
    // Stock generoso por defecto en todas las sucursales — el admin lo ajusta fino después
    // desde Inventario, esto solo evita que nazca "agotado" y bloquee al cajero de entrada.
    const stockByBranch = Object.fromEntries(branches.map((b) => [b.id, 50]));
    const extra = createTopping({
      name: newExtraName.trim(),
      priceExtra: Number(newExtraPrice) || 0,
      stockByBranch,
      lowStockThreshold: 5,
    });
    setForm((f) => ({ ...f, toppingIds: [...f.toppingIds, extra.id] }));
    setNewExtraName('');
    setNewExtraPrice('');
  }

  function handleSave() {
    if (!form.name.trim()) return;
    const stockByBranch = product
      ? product.stockByBranch
      : Object.fromEntries(branches.map((b) => [b.id, Number(form.stock) || 0]));

    // El primer tamaño de la lista define el "precio base" del producto; los siguientes se
    // guardan como delta sobre ese primero (así el resto de la app — POS, carrito, ticket —
    // sigue calculando basePrice + size.priceDelta sin ningún cambio).
    const rows = form.sizes.filter((s) => s.label.trim());
    const validRows = rows.length ? rows : form.sizes;
    const basePrice = Number(validRows[0]?.price) || 0;
    const sizes: SizeOption[] = validRows.map((s) => ({
      id: s.id,
      label: s.label.trim() || 'Único',
      priceDelta: (Number(s.price) || 0) - basePrice,
    }));

    const base = {
      name: form.name.trim(),
      category: form.category,
      description: form.description,
      basePrice,
      gradient: form.gradient,
      emoji: form.emoji,
      sizes,
      // La pollería no maneja bases líquidas ni nivel de azúcar (herencia de la juguería
      // original) — quedan siempre vacío/false para que ningún producto nuevo los active.
      baseLiquidaOptions: [],
      allowSugarLevel: false,
      toppingIds: form.toppingIds,
      active: product?.active ?? true,
      stockByBranch,
      lowStockThreshold: Number(form.lowStockThreshold) || 0,
      unit: 'porciones',
    };
    if (product) {
      upsertProduct({ ...base, id: product.id });
    } else {
      createProduct(base);
    }
    onClose();
  }

  return (
    <Modal open={open} onClose={onClose} title={product ? 'Editar producto' : 'Nuevo producto'} size="lg">
      <div className="grid grid-cols-1 gap-5 px-6 pb-6 pt-2 sm:grid-cols-2">
        <Input label="Nombre" value={form.name} onChange={(e) => setForm((f) => ({ ...f, name: e.target.value }))} />

        <label className="flex flex-col">
          <span className={fieldLabelClasses}>Categoría</span>
          <select
            value={form.category}
            onChange={(e) => setForm((f) => ({ ...f, category: e.target.value }))}
            className={cn(fieldClasses, 'min-h-touch')}
          >
            {[...new Set([...CATEGORIES, form.category])].map((c) => (
              <option key={c} value={c}>
                {c}
              </option>
            ))}
          </select>
        </label>

        <div className="sm:col-span-2">
          <label className="flex flex-col">
            <span className={fieldLabelClasses}>Descripción</span>
            <textarea
              value={form.description}
              onChange={(e) => setForm((f) => ({ ...f, description: e.target.value }))}
              rows={2}
              className={cn(fieldClasses, 'text-sm')}
            />
          </label>
        </div>

        {product ? (
          <div>
            <p className={fieldLabelClasses}>Stock</p>
            <p className="flex min-h-touch items-center rounded-xl border border-border-strong bg-field px-4 text-sm text-ink-muted">
              Se ajusta por sucursal desde Inventario.
            </p>
          </div>
        ) : (
          <Input
            label="Stock inicial (todas las sucursales)"
            type="number"
            min={0}
            value={form.stock}
            onChange={(e) => setForm((f) => ({ ...f, stock: e.target.value }))}
          />
        )}
        <Input
          label="Umbral de stock bajo"
          type="number"
          min={0}
          value={form.lowStockThreshold}
          onChange={(e) => setForm((f) => ({ ...f, lowStockThreshold: e.target.value }))}
        />

        <div className="sm:col-span-2">
          <div className="mb-2 flex items-center justify-between">
            <p className={cn(fieldLabelClasses, 'mb-0')}>Tamaños / Variantes</p>
            <button
              type="button"
              onClick={addSizeRow}
              className="flex items-center gap-1 rounded-full bg-primary-50 px-3 py-1.5 text-xs font-bold text-primary-700 hover:bg-primary-100 cursor-pointer dark:bg-primary-500/15 dark:text-primary-300 dark:hover:bg-primary-500/25"
            >
              <Plus size={14} /> Agregar tamaño
            </button>
          </div>
          <div className="space-y-2">
            {form.sizes.map((s, i) => (
              <div key={s.id} className="flex items-center gap-2">
                <input
                  value={s.label}
                  onChange={(e) => updateSizeRow(i, { label: e.target.value })}
                  placeholder={i === 0 ? 'Ej. Único, Personal…' : 'Ej. Mediano, Familiar, 2L…'}
                  className={cn(fieldClasses, 'flex-1 text-sm')}
                />
                <input
                  type="number"
                  min={0}
                  step={0.5}
                  value={s.price}
                  onChange={(e) => updateSizeRow(i, { price: e.target.value })}
                  placeholder="Precio"
                  className={cn(fieldClasses, 'w-24 text-sm sm:w-28')}
                />
                <button
                  type="button"
                  onClick={() => removeSizeRow(i)}
                  disabled={form.sizes.length <= 1}
                  className="flex h-11 w-11 flex-shrink-0 items-center justify-center rounded-xl text-ink-muted hover:bg-red-50 hover:text-red-600 disabled:cursor-not-allowed disabled:opacity-30 disabled:hover:bg-transparent disabled:hover:text-ink-muted cursor-pointer"
                  aria-label="Quitar tamaño"
                >
                  <X size={16} />
                </button>
              </div>
            ))}
          </div>
          <p className="mt-1.5 text-xs text-ink-soft">
            Con un solo tamaño no aparece selector en el POS: se cobra ese precio directo. Con
            dos o más, el cajero elige entre botones al agregar el producto al pedido.
          </p>
        </div>

        <div className="sm:col-span-2">
          <p className={fieldLabelClasses}>Ícono</p>
          <div className="grid grid-cols-6 gap-2 sm:grid-cols-8">
            {EMOJI_OPTIONS.map((e) => (
              <button
                key={e}
                type="button"
                onClick={() => setForm((f) => ({ ...f, emoji: e }))}
                className={cn(
                  'flex h-11 w-11 items-center justify-center rounded-xl border text-xl cursor-pointer transition-colors',
                  form.emoji === e
                    ? 'border-transparent bg-amber-500/10 ring-2 ring-amber-500'
                    : 'border-zinc-300 bg-zinc-50 hover:border-amber-300 dark:border-zinc-700 dark:bg-zinc-800',
                )}
              >
                {e}
              </button>
            ))}
          </div>
        </div>

        <div className="sm:col-span-2">
          <p className={fieldLabelClasses}>Color de tarjeta</p>
          <div className="grid grid-cols-6 gap-2 sm:grid-cols-8">
            {GRADIENT_OPTIONS.map((g) => (
              <button
                key={g}
                type="button"
                onClick={() => setForm((f) => ({ ...f, gradient: g }))}
                aria-label={g}
                className={cn(
                  'h-11 rounded-xl bg-gradient-to-br cursor-pointer border-2 transition-all',
                  g,
                  form.gradient === g ? 'border-white ring-2 ring-amber-500 scale-105 dark:border-zinc-900' : 'border-transparent',
                )}
              />
            ))}
          </div>
        </div>

        <div className="sm:col-span-2">
          <p className={fieldLabelClasses}>Agregados / Extras disponibles</p>
          <div className="flex flex-wrap gap-2">
            {toppings.map((t) => (
              <button
                key={t.id}
                type="button"
                onClick={() => toggleTopping(t.id)}
                className={cn(
                  'rounded-full border px-3.5 py-2 text-sm transition-colors cursor-pointer',
                  form.toppingIds.includes(t.id) ? optionActiveClasses : optionInactiveClasses,
                )}
              >
                {t.name}
              </button>
            ))}
            {toppings.length === 0 && <p className="text-sm text-ink-soft">Todavía no hay agregados creados.</p>}
          </div>

          {/* Crear un agregado nuevo (nombre + precio) sin salir del modal — queda disponible
              de inmediato para este producto y para cualquier otro. */}
          <div className="mt-3 flex items-center gap-2 rounded-xl2 border-2 border-dashed border-border-strong bg-field p-2.5">
            <input
              value={newExtraName}
              onChange={(e) => setNewExtraName(e.target.value)}
              placeholder="Nuevo agregado (ej. Mayonesa casera)"
              className={cn(fieldClasses, 'flex-1 border-none bg-transparent text-sm')}
            />
            <input
              type="number"
              min={0}
              step={0.5}
              value={newExtraPrice}
              onChange={(e) => setNewExtraPrice(e.target.value)}
              placeholder="Precio"
              className={cn(fieldClasses, 'w-20 border-none bg-transparent text-sm')}
            />
            <button
              type="button"
              onClick={handleCreateExtra}
              disabled={!newExtraName.trim()}
              className="flex h-11 w-11 flex-shrink-0 items-center justify-center rounded-xl bg-primary-500 text-white hover:bg-primary-600 disabled:cursor-not-allowed disabled:opacity-40 cursor-pointer"
              aria-label="Crear agregado"
            >
              <Plus size={18} />
            </button>
          </div>
        </div>
      </div>

      <div className="sticky bottom-0 flex items-center gap-3 border-t border-border bg-surface px-6 py-4">
        <Button
          variant="outline"
          onClick={onClose}
          className="flex-1 border-transparent bg-zinc-100 text-zinc-700 hover:bg-zinc-200 dark:bg-zinc-800 dark:text-zinc-300 dark:hover:bg-zinc-700"
        >
          Cancelar
        </Button>
        <Button
          onClick={handleSave}
          className="flex-[2] !bg-amber-500 py-3 !text-white !shadow-lg hover:!bg-amber-600"
          size="lg"
          disabled={!form.name.trim()}
        >
          Guardar producto
        </Button>
      </div>
    </Modal>
  );
}
