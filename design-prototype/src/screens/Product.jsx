import { useState } from 'react';
import { AVAILABILITY, STORES, ago, soles } from '../data.js';
import { StoreBadge } from '../components/Brand.jsx';
import Icon from '../components/Icon.jsx';
import ProductArt from '../components/ProductArt.jsx';
import PriceChart from '../components/PriceChart.jsx';
import AlertSheet from '../components/AlertSheet.jsx';
import { FavButton } from '../components/ProductCard.jsx';

export default function Product({ p, back, saved, toggleSave, alertTarget, setAlert, notify }) {
  const [sheet, setSheet] = useState(false);
  const best = p.best;
  const bestStore = STORES[best.store];
  const inStock = p.offers.filter((o) => o.availability !== 'out');
  const min = best.price;
  const max = Math.max(...inStock.map((o) => o.price));
  const goStore = (code) => notify(`Se abriría ${STORES[code].name} en el navegador`);

  return (
    <div className="detail">
      <main className="view view-detail">
        <div className="detail-top">
          <button className="icon-btn icon-btn-solid" aria-label="Volver" onClick={back}>
            <Icon name="back" />
          </button>
          <div className="detail-top-actions">
            <button className="icon-btn icon-btn-solid" aria-label="Compartir" onClick={() => notify('Enlace copiado')}>
              <Icon name="share" size={20} />
            </button>
            <FavButton on={saved.has(p.id)} onToggle={() => toggleSave(p.id)} className="fav-lg" />
          </div>
        </div>

        <div className="detail-art">
          <ProductArt image={p.image} kind={p.kind} />
          {p.discount > 0 && !p.stale && <span className="badge-off">-{p.discount}%</span>}
        </div>

        <section className="detail-head">
          <p className="brand">{p.brand}</p>
          <h1>{p.title}</h1>

          <div className="best">
            <div>
              <p className="best-label">{p.stale ? 'Último precio visto' : 'Precio más bajo'}</p>
              <p className={`best-price ${p.stale ? 'is-stale' : ''}`}>{soles(best.price)}</p>
              {best.prev && !p.stale && <p className="was">Antes {soles(best.prev)}</p>}
            </div>
            <div className="best-store">
              <StoreBadge code={best.store} size={36} />
              <span>en {bestStore.name}</span>
            </div>
          </div>

          {p.savings > 0 && !p.stale && (
            <p className="savings">
              <Icon name="check" size={18} stroke={2.4} />
              Ahorras {soles(p.savings)} frente a {STORES[p.priciest.store].name}
            </p>
          )}
          <p className={`fresh ${p.stale ? 'is-stale' : ''}`}>
            {p.stale
              ? `Precio por confirmar: lo vimos ${ago(best.hours)}. Revisa en la tienda antes de comprar.`
              : `Verificado ${ago(best.hours)}`}
          </p>
        </section>

        <section className="block">
          <h2>
            Precios en {p.offers.length} {p.offers.length === 1 ? 'tienda' : 'tiendas'}
          </h2>
          <ol className="ladder">
            {p.offers.map((o, i) => {
              const out = o.availability === 'out';
              const single = p.offers.length === 1;
              const isBest = i === 0 && !out && !single;
              const width = out ? 0 : max === min ? 100 : 40 + (60 * (o.price - min)) / (max - min);
              return (
                <li key={o.store} className={`${isBest ? 'is-best' : ''} ${out ? 'is-out' : ''}`}>
                  <button className="ladder-row" onClick={() => goStore(o.store)}>
                    <StoreBadge code={o.store} size={36} />
                    <div className="ladder-main">
                      <div className="ladder-line">
                        <span className="ladder-store">{STORES[o.store].name}</span>
                        <span className="ladder-price">{soles(o.price)}</span>
                      </div>
                      {!single && (
                        <div className="bar">
                          <span style={{ width: `${width}%` }} />
                        </div>
                      )}
                      <div className="ladder-meta">
                        <span>
                          {AVAILABILITY[o.availability]}
                          {o.shipping === 0 && ', envío gratis'}
                          {o.shipping > 0 && `, envío ${soles(o.shipping)}`}
                        </span>
                        <span className="ladder-diff">
                          {single ? 'Única tienda por ahora' : isBest ? 'Más barato' : out ? '' : `+${soles(o.price - min)}`}
                        </span>
                      </div>
                    </div>
                    <Icon name="external" size={18} className="ladder-go" />
                  </button>
                </li>
              );
            })}
          </ol>
        </section>

        <section className="block">
          <h2>Historial de precio</h2>
          <PriceChart history={p.history} stale={p.stale} />
        </section>

        {p.specs.length > 0 && (
          <section className="block">
            <h2>Características</h2>
            <dl className="specs">
              {p.specs.map(([k, v]) => (
                <div key={k}>
                  <dt>{k}</dt>
                  <dd>{v}</dd>
                </div>
              ))}
            </dl>
          </section>
        )}

        <p className="disclaimer">
          Cada tienda publica sus propios precios y pueden cambiar. Confirma el total antes de pagar.
        </p>
      </main>

      <div className="action-bar">
        <button className={`btn btn-quiet ${alertTarget ? 'has-alert' : ''}`} onClick={() => setSheet(true)}>
          <Icon name="bell" size={20} filled={!!alertTarget} />
          {alertTarget ? `Bajo ${soles(alertTarget)}` : 'Avisarme si baja'}
        </button>
        <button className="btn btn-primary" onClick={() => goStore(best.store)}>
          Ir a {bestStore.name}
          <Icon name="external" size={18} />
        </button>
      </div>

      {sheet && (
        <AlertSheet
          p={p}
          current={alertTarget}
          onClose={() => setSheet(false)}
          onSave={(v) => {
            setAlert(p.id, v);
            setSheet(false);
            notify(`Alerta creada: te avisamos si baja de ${soles(v)}`);
          }}
          onRemove={() => {
            setAlert(p.id, null);
            setSheet(false);
            notify('Alerta quitada');
          }}
        />
      )}
    </div>
  );
}
