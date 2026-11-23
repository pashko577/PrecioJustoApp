import { useState } from 'react';
import { STORES, soles } from '../data.js';
import Icon from './Icon.jsx';

export default function AlertSheet({ p, current, onSave, onRemove, onClose }) {
  const suggested = Math.floor(p.best.price * 0.9);
  const [value, setValue] = useState(String(current ?? suggested));
  const n = Number(value);
  const valid = n > 0 && n < p.best.price;

  return (
    <div className="sheet-backdrop" onClick={onClose}>
      <div className="sheet" role="dialog" aria-modal="true" aria-labelledby="sheet-title" onClick={(e) => e.stopPropagation()}>
        <div className="sheet-grip" />
        <div className="sheet-head">
          <h2 id="sheet-title">Avísame cuando baje</h2>
          <button className="icon-btn" aria-label="Cerrar" onClick={onClose}>
            <Icon name="close" />
          </button>
        </div>
        <p className="sheet-text">
          Hoy el precio más bajo es {soles(p.best.price)} en {STORES[p.best.store].name}. Te enviamos una notificación
          cuando alguna tienda lo publique a tu precio o menos.
        </p>
        <label className="money-field">
          <span>S/</span>
          <input
            inputMode="decimal"
            value={value}
            onChange={(e) => setValue(e.target.value.replace(/[^\d.]/g, ''))}
            aria-label="Precio objetivo en soles"
          />
        </label>
        {!valid && value !== '' && (
          <p className="field-error">Pon un precio menor a {soles(p.best.price)}.</p>
        )}
        <div className="chip-row">
          {[5, 10, 15].map((pct) => {
            const v = Math.floor(p.best.price * (1 - pct / 100));
            return (
              <button key={pct} className="chip" aria-pressed={n === v} onClick={() => setValue(String(v))}>
                {soles(v)} <span className="chip-note">-{pct}%</span>
              </button>
            );
          })}
        </div>
        <button className="btn btn-primary btn-block" disabled={!valid} onClick={() => onSave(n)}>
          {current ? 'Actualizar alerta' : 'Crear alerta'}
        </button>
        {current && (
          <button className="btn btn-quiet btn-block" onClick={onRemove}>
            Quitar alerta
          </button>
        )}
      </div>
    </div>
  );
}
