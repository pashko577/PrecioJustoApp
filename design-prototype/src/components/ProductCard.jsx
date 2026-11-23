import { STORES, soles } from '../data.js';
import { StoreBadge } from './Brand.jsx';
import Icon from './Icon.jsx';
import ProductArt from './ProductArt.jsx';

export function FavButton({ on, onToggle, className = '' }) {
  return (
    <button
      className={`fav ${on ? 'is-on' : ''} ${className}`}
      aria-pressed={on}
      aria-label={on ? 'Quitar de guardados' : 'Guardar'}
      onClick={(e) => {
        e.stopPropagation();
        onToggle();
      }}
    >
      <Icon name="heart" size={18} filled={on} />
    </button>
  );
}

export default function ProductCard({ p, open, saved, toggleSave }) {
  const store = STORES[p.best.store];
  const n = p.offers.length;
  return (
    <article
      className="card"
      tabIndex={0}
      onClick={() => open(p.id)}
      onKeyDown={(e) => e.key === 'Enter' && open(p.id)}
    >
      <div className="card-art">
        <ProductArt image={p.image} kind={p.kind} />
        {p.discount > 0 && !p.stale && <span className="badge-off">-{p.discount}%</span>}
        <FavButton on={saved.has(p.id)} onToggle={() => toggleSave(p.id)} />
      </div>
      <div className="card-body">
        <p className="brand">{p.brand}</p>
        <h3 className="card-title">{p.shortName}</h3>
        {p.stale ? (
          <p className="price-pending">Precio por confirmar</p>
        ) : (
          <p className="price">{soles(p.best.price)}</p>
        )}
        <div className="card-store">
          <StoreBadge code={p.best.store} size={18} />
          <span className="card-store-name">{store.name}</span>
          <span className="card-store-count">
            {n} {n === 1 ? 'tienda' : 'tiendas'}
          </span>
        </div>
      </div>
    </article>
  );
}
