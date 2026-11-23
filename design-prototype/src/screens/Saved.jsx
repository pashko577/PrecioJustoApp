import { STORES, soles } from '../data.js';
import { StoreBadge } from '../components/Brand.jsx';
import Icon from '../components/Icon.jsx';
import ProductArt from '../components/ProductArt.jsx';

export default function Saved({ products, saved, alerts, open, goSearch }) {
  const list = products.filter((p) => saved.has(p.id));

  return (
    <main className="view">
      <h1 className="screen-title">Guardados</h1>
      {list.length === 0 ? (
        <div className="empty">
          <span className="empty-icon">
            <Icon name="heart" size={28} />
          </span>
          <h2>Aún no guardas productos</h2>
          <p>Toca el corazón en cualquier producto para seguir su precio y verlo aquí.</p>
          <button className="btn btn-primary" onClick={() => goSearch()}>
            Buscar productos
          </button>
        </div>
      ) : (
        <ul className="saved-list">
          {list.map((p) => {
            const target = alerts[p.id];
            const reached = target && p.best.price <= target;
            return (
              <li key={p.id}>
                <button className="saved-row" onClick={() => open(p.id)}>
                  <span className="saved-art">
                    <ProductArt image={p.image} kind={p.kind} />
                  </span>
                  <span className="saved-main">
                    <span className="saved-title">{p.shortName}</span>
                    <span className="saved-price">
                      {p.stale ? 'Precio por confirmar' : soles(p.best.price)}
                      {p.discount > 0 && !p.stale && <span className="mini-off">-{p.discount}%</span>}
                    </span>
                    <span className="saved-store">
                      <StoreBadge code={p.best.store} size={16} />
                      {STORES[p.best.store].name}
                    </span>
                    {target ? (
                      <span className={`saved-alert ${reached ? 'is-reached' : ''}`}>
                        <Icon name="bell" size={14} filled />
                        {reached ? 'Llegó a tu precio' : `Te avisamos bajo ${soles(target)}`}
                      </span>
                    ) : (
                      <span className="saved-alert is-none">Sin alerta de precio</span>
                    )}
                  </span>
                </button>
              </li>
            );
          })}
        </ul>
      )}
    </main>
  );
}
