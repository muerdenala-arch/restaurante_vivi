import { useEffect, useRef } from 'react';
import { motion } from 'framer-motion';
import { CheckCircle2, Printer, Receipt } from 'lucide-react';
import { Modal } from '@/components/ui/Modal';
import { Button } from '@/components/ui/Button';
import type { Sale } from '@/types';
import { BASE_LIQUIDA_LABEL, NIVEL_AZUCAR_LABEL } from '@/types';
import { cn, formatCurrency, formatDateTime } from '@/lib/utils';
import { APP_CONFIG } from '@/config/app';
import { useBranchStore } from '@/store/branchStore';
import { logoGlowClasses } from '@/lib/brand';

interface TicketProps {
  sale: Sale | null;
  onClose: () => void;
}

export function Ticket({ sale, onClose }: TicketProps) {
  const branch = useBranchStore((s) => s.branches.find((b) => b.id === sale?.branchId));
  // Dispara la impresión térmica sola apenas se confirma el cobro — el botón "Imprimir"
  // de abajo queda disponible para reimprimir, pero el cajero ya no tiene que acordarse
  // de tocarlo la primera vez. El ref evita reabrir el diálogo de impresión en cada
  // re-render mientras el mismo ticket sigue en pantalla.
  const printedSaleId = useRef<string | null>(null);
  const receiptRef = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!sale || printedSaleId.current === sale.id) return;
    printedSaleId.current = sale.id;
    // El efecto ya corre después de que React montó el DOM (`#thermal-receipt` existe acá),
    // pero se espera un doble rAF para garantizar que el navegador ya pintó ese frame antes
    // de abrir el diálogo de impresión — evita el "ticket en blanco" ocasional cuando
    // window.print() se dispara en el mismo tick que el commit.
    let raf1 = 0;
    let raf2 = 0;
    raf1 = requestAnimationFrame(() => {
      raf2 = requestAnimationFrame(() => {
        if (receiptRef.current) window.print();
      });
    });
    return () => {
      cancelAnimationFrame(raf1);
      cancelAnimationFrame(raf2);
    };
  }, [sale]);

  if (!sale) return null;

  return (
    <Modal open={!!sale} onClose={onClose} size="sm">
      <div className="px-6 pb-6 pt-6">
        <motion.div
          initial={{ scale: 0.6, opacity: 0 }}
          animate={{ scale: 1, opacity: 1 }}
          transition={{ type: 'spring', stiffness: 350, damping: 18 }}
          className="mx-auto mb-3 flex h-16 w-16 items-center justify-center rounded-full bg-secondary-100 text-secondary-600"
        >
          <CheckCircle2 size={36} />
        </motion.div>
        <p className="mb-5 text-center font-display text-lg font-bold text-ink">Venta completada</p>

        <div
          id="thermal-receipt"
          ref={receiptRef}
          className="rounded-xl2 border-2 border-dashed border-border bg-cream-100 p-4 font-mono text-xs text-ink"
        >
          <div className="mb-2 text-center">
            <img
              src="/logo.png"
              alt={APP_CONFIG.storeName}
              className={cn('mx-auto mb-1.5 h-8 w-auto object-contain', logoGlowClasses)}
            />
            <p className="font-display text-sm font-extrabold tracking-tight">{APP_CONFIG.storeName}</p>
            {branch && (
              <>
                <p className="text-[11px] font-semibold text-ink-muted">{branch.name}</p>
                <p className="text-[11px] text-ink-muted">{branch.address}</p>
              </>
            )}
            <p className="text-[11px] text-ink-muted">Ticket #{sale.ticketNumber}</p>
            <p className="text-[11px] text-ink-muted">{formatDateTime(sale.createdAt)}</p>
            <p className="text-[11px] text-ink-muted">Cajero: {sale.cashierName}</p>
          </div>
          <div className="my-2 border-t border-dashed border-ink-soft/50" />
          {sale.items.map((item) => (
            <div key={item.lineId} className="mb-1.5">
              <div className="flex justify-between font-semibold">
                <span>
                  {item.quantity}x {item.product.name} ({item.modifiers.size.label})
                </span>
                <span>{formatCurrency(item.lineTotal)}</span>
              </div>
              <p className="text-[10px] text-ink-muted">
                {[
                  item.modifiers.baseLiquida && BASE_LIQUIDA_LABEL[item.modifiers.baseLiquida],
                  item.modifiers.sugarLevel && NIVEL_AZUCAR_LABEL[item.modifiers.sugarLevel],
                  ...item.modifiers.toppings.map((t) => t.name),
                ]
                  .filter(Boolean)
                  .join(' · ')}
              </p>
            </div>
          ))}
          <div className="my-2 border-t border-dashed border-ink-soft/50" />
          <div className="flex justify-between font-bold">
            <span>TOTAL</span>
            <span>{formatCurrency(sale.total)}</span>
          </div>
          <div className="mt-1 flex justify-between text-ink-muted">
            <span>Pago</span>
            <span className="uppercase">{sale.payment.method === 'efectivo' ? 'Efectivo' : APP_CONFIG.qrProviderLabel}</span>
          </div>
          {sale.payment.method === 'qr' && (
            <div className="flex justify-between text-ink-muted">
              <span>Comprobante</span>
              <span>{sale.payment.receiptImage ? 'Adjunto' : 'Sin adjuntar'}</span>
            </div>
          )}
          <div className="my-2 border-t border-dashed border-ink-soft/50" />
          <p className="text-center text-[11px]">{APP_CONFIG.ticketFooter}</p>
        </div>

        <div className="mt-5 flex gap-3">
          <Button variant="outline" className="flex-1" onClick={() => window.print()}>
            <Printer size={16} /> Imprimir
          </Button>
          <Button className="flex-1" onClick={onClose}>
            <Receipt size={16} /> Nueva venta
          </Button>
        </div>
      </div>
    </Modal>
  );
}
