import Icon from '../components/Icon.jsx';
import ProductArt from '../components/ProductArt.jsx';

const TYPE_ICON = { drop: 'down', stores: 'store', stock: 'layers' };

export default function Alerts({ feed, products, open, markAllRead }) {
  const byId = Object.fromEntries(products.map((p) => [p.id, p]));
  const unread = feed.filter((f) => f.unread).length;

  return (
    <main className="view">
      <div className="screen-head">
        <h1 className="screen-title">Alertas</h1>
        {unread > 0 && (
          <button className="link" onClick={markAllRead}>
            Marcar como leídas
          </button>
        )}
      </div>
      {feed.length === 0 ? (
        <div className="empty">
          <span className="empty-icon">
            <Icon name="bell" size={28} />
          </span>
          <h2>Sin novedades por ahora</h2>
          <p>Crea una alerta desde un producto y te avisamos aquí cuando baje de precio.</p>
        </div>
      ) : (
        <ul className="feed">
          {feed.map((f) => {
            const p = byId[f.productId];
            if (!p) return null;
            return (
              <li key={f.id} className={f.unread ? 'is-unread' : ''}>
                <button className="feed-row" onClick={() => open(p.id)}>
                  <span className="feed-art">
                    <ProductArt image={p.image} kind={p.kind} />
                    <span className={`feed-type type-${f.type}`}>
                      <Icon name={TYPE_ICON[f.type]} size={12} stroke={2.4} />
                    </span>
                  </span>
                  <span className="feed-main">
                    <span className="feed-title">{f.title}</span>
                    <span className="feed-product">{p.shortName}</span>
                    <span className="feed-body">{f.body}</span>
                    <span className="feed-when">{f.when}</span>
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
