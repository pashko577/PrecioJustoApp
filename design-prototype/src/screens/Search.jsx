import { useState } from 'react';
import { CATEGORIES, POPULAR_SEARCHES, STORES, normalize } from '../data.js';
import { StoreBadge } from '../components/Brand.jsx';
import Icon from '../components/Icon.jsx';
import ProductCard from '../components/ProductCard.jsx';

const SORTS = [
  { id: 'price', label: 'Menor precio' },
  { id: 'discount', label: 'Mayor descuento' },
  { id: 'stores', label: 'Más tiendas' },
];

export default function Search({ products, open, filters, setFilters, recentQueries, clearRecentQueries, saved, toggleSave, notify }) {
  const [sort, setSort] = useState('price');
  const { q, stores, category } = filters;
  const set = (patch) => setFilters({ ...filters, ...patch });

  const tokens = normalize(q).split(/\s+/).filter(Boolean);
  let results = products.filter((p) => {
    const hay = normalize(`${p.brand} ${p.title}`);
    return (
      tokens.every((t) => hay.includes(t)) &&
      (!category || p.category === category) &&
      (stores.length === 0 || p.offers.some((o) => stores.includes(o.store)))
    );
  });
  results = [...results].sort((a, b) =>
    sort === 'price' ? a.best.price - b.best.price : sort === 'discount' ? b.discount - a.discount : b.offers.length - a.offers.length,
  );
  const toggleStore = (code) =>
    set({ stores: stores.includes(code) ? stores.filter((s) => s !== code) : [...stores, code] });
  const catName = CATEGORIES.find((c) => c.slug === category)?.name;
  const hasFilters = stores.length > 0 || category;

  return (
    <main className="view">
      <h1 className="screen-title">Buscar</h1>
      <div className="search-head">
        <label className="search-input">
          <Icon name="search" size={20} />
          <input
            autoFocus={!hasFilters}
            value={q}
            onChange={(e) => set({ q: e.target.value })}
            placeholder="Producto, marca o código"
            aria-label="Buscar productos"
          />
          {q && (
            <button className="icon-btn icon-btn-sm" aria-label="Borrar búsqueda" onClick={() => set({ q: '' })}>
              <Icon name="close" size={18} />
            </button>
          )}
        </label>
        <button
          className="icon-btn icon-btn-solid"
          aria-label="Escanear código de barras"
          onClick={() => notify('Aquí se abre la cámara para leer el código de barras')}
        >
          <Icon name="scan" />
        </button>
      </div>

      {!q && (
        <div className="discover">
          {recentQueries.length > 0 && (
            <>
              <div className="discover-head">
                <p className="filter-label">Buscaste</p>
                <button className="link" onClick={clearRecentQueries}>
                  Borrar
                </button>
              </div>
              <div className="chip-row">
                {recentQueries.map((t) => (
                  <button key={t} className="chip chip-soft" onClick={() => set({ q: t })}>
                    <Icon name="search" size={14} />
                    {t}
                  </button>
                ))}
              </div>
            </>
          )}
          <p className="filter-label">Lo más buscado</p>
          <div className="chip-row">
            {POPULAR_SEARCHES.map((t) => (
              <button key={t} className="chip chip-soft" onClick={() => set({ q: t })}>
                {t}
              </button>
            ))}
          </div>
        </div>
      )}

      <div className="filter-block">
        <p className="filter-label">Ordenar</p>
        <div className="chip-row chip-scroll">
          {SORTS.map((s) => (
            <button key={s.id} className="chip" aria-pressed={sort === s.id} onClick={() => setSort(s.id)}>
              {s.label}
            </button>
          ))}
        </div>
        <p className="filter-label">Tiendas</p>
        <div className="chip-row chip-scroll">
          {Object.entries(STORES).map(([code, s]) => (
            <button key={code} className="chip chip-store" aria-pressed={stores.includes(code)} onClick={() => toggleStore(code)}>
              <StoreBadge code={code} size={20} />
              {s.name}
            </button>
          ))}
        </div>
      </div>

      <div className="result-bar">
        <p>
          {results.length} {results.length === 1 ? 'producto' : 'productos'}
          {catName && ` en ${catName}`}
        </p>
        {hasFilters && (
          <button className="link" onClick={() => set({ stores: [], category: null })}>
            Quitar filtros
          </button>
        )}
      </div>

      {results.length > 0 ? (
        <div className="grid">
          {results.map((p) => (
            <ProductCard key={p.id} p={p} open={open} saved={saved} toggleSave={toggleSave} />
          ))}
        </div>
      ) : (
        <div className="empty">
          <span className="empty-icon">
            <Icon name="search" size={28} />
          </span>
          <h2>{q ? `No encontramos «${q}»` : 'No hay productos con estos filtros'}</h2>
          <p>
            {q
              ? 'Prueba solo con la marca y el modelo, por ejemplo «Teros 2417», o escanea el código de barras de la caja.'
              : 'Quita alguna tienda o categoría para ver más resultados.'}
          </p>
          {hasFilters && (
            <button className="btn btn-quiet" onClick={() => set({ stores: [], category: null })}>
              Quitar filtros
            </button>
          )}
        </div>
      )}
    </main>
  );
}
