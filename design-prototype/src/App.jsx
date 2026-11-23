import { useEffect, useMemo, useState } from 'react';
import { INITIAL_FEED, PRODUCTS, WORST_CASE, buildProduct } from './data.js';
import Icon from './components/Icon.jsx';
import Home from './screens/Home.jsx';
import Search from './screens/Search.jsx';
import Product from './screens/Product.jsx';
import Saved from './screens/Saved.jsx';
import Alerts from './screens/Alerts.jsx';
import Profile from './screens/Profile.jsx';

const TABS = [
  { id: 'home', label: 'Inicio', icon: 'home' },
  { id: 'search', label: 'Buscar', icon: 'search' },
  { id: 'saved', label: 'Guardados', icon: 'heart' },
  { id: 'alerts', label: 'Alertas', icon: 'bell' },
  { id: 'profile', label: 'Perfil', icon: 'user' },
];
const NO_FILTERS = { q: '', stores: [], category: null };
// Atajos para abrir una pantalla directa: ?tab=search, ?p=teros-te2417s, ?worst=1
const params = new URLSearchParams(window.location.search);

export default function App() {
  const [tab, setTab] = useState(params.get('tab') ?? 'home');
  const [productId, setProductId] = useState(params.get('p'));
  const [filters, setFilters] = useState({ ...NO_FILTERS, q: params.get('q') ?? '' });
  const [saved, setSaved] = useState(() => new Set(['teros-te2417s', 'kingston-a400', 'zte-a35e']));
  const [alerts, setAlerts] = useState({ 'teros-te2417s': 249, 'zte-a35e': 349 });
  const [feed, setFeed] = useState(INITIAL_FEED);
  const [worst, setWorst] = useState(params.get('worst') === '1');
  const [toast, setToast] = useState(null);
  const [recent, setRecent] = useState(['sony-whch520', 'blackline-refri-417']);
  const [recentQueries, setRecentQueries] = useState(['teros 24', 'freidora']);
  const [hiddenStores, setHiddenStores] = useState(() => new Set());
  const [prefs, setPrefs] = useState({ drops: true, stock: true, weekly: false });

  // Las tiendas desactivadas en Perfil desaparecen de la comparación.
  const products = useMemo(() => {
    const base = worst ? [WORST_CASE, ...PRODUCTS] : PRODUCTS;
    if (hiddenStores.size === 0) return base;
    return base
      .map((p) => ({ ...p, offers: p.offers.filter((o) => !hiddenStores.has(o.store)) }))
      .filter((p) => p.offers.length > 0)
      .map(buildProduct);
  }, [worst, hiddenStores]);
  const product = products.find((p) => p.id === productId);
  const unread = feed.filter((f) => f.unread).length;

  useEffect(() => {
    if (!toast) return;
    const t = setTimeout(() => setToast(null), 2600);
    return () => clearTimeout(t);
  }, [toast]);

  const notify = (text) => setToast({ text, key: Date.now() });
  const open = (id) => {
    setProductId(id);
    setRecent((r) => [id, ...r.filter((x) => x !== id)].slice(0, 8));
    if (filters.q.trim().length > 1)
      setRecentQueries((r) => [filters.q.trim(), ...r.filter((x) => x !== filters.q.trim())].slice(0, 5));
  };
  const toggleStoreVisible = (code) => {
    const next = new Set(hiddenStores);
    if (next.has(code)) next.delete(code);
    else next.add(code);
    setHiddenStores(next);
  };
  const toggleSave = (id) => {
    const next = new Set(saved);
    if (next.has(id)) {
      next.delete(id);
      notify('Quitado de guardados');
    } else {
      next.add(id);
      notify('Guardado. Lo verás en Guardados');
    }
    setSaved(next);
  };
  const setAlert = (id, value) => {
    setAlerts((a) => {
      const next = { ...a };
      if (value == null) delete next[id];
      else next[id] = value;
      return next;
    });
    if (value != null) setSaved((s) => new Set(s).add(id));
  };
  const goSearch = ({ store, category, scan } = {}) => {
    setFilters({ ...NO_FILTERS, stores: store ? [store] : [], category: category ?? null });
    setProductId(null);
    setTab('search');
    if (scan) notify('Aquí se abre la cámara para leer el código de barras');
  };
  const goTab = (id) => {
    setProductId(null);
    if (id === 'search' && tab !== 'search') setFilters(NO_FILTERS);
    setTab(id);
  };

  const shared = { products, open, saved, toggleSave, notify };
  let screen;
  if (product) {
    screen = (
      <Product
        key={product.id}
        p={product}
        back={() => setProductId(null)}
        alertTarget={alerts[product.id]}
        setAlert={setAlert}
        {...shared}
      />
    );
  } else if (tab === 'home') {
    screen = <Home goSearch={goSearch} goAlerts={() => goTab('alerts')} unread={unread} recent={recent} {...shared} />;
  } else if (tab === 'search') {
    screen = (
      <Search
        filters={filters}
        setFilters={setFilters}
        recentQueries={recentQueries}
        clearRecentQueries={() => setRecentQueries([])}
        {...shared}
      />
    );
  } else if (tab === 'saved') {
    screen = <Saved alerts={alerts} goSearch={goSearch} {...shared} />;
  } else if (tab === 'profile') {
    screen = (
      <Profile
        prefs={prefs}
        setPrefs={setPrefs}
        hiddenStores={hiddenStores}
        toggleStoreVisible={toggleStoreVisible}
        notify={notify}
      />
    );
  } else {
    screen = (
      <Alerts
        feed={feed}
        markAllRead={() => setFeed(feed.map((f) => ({ ...f, unread: false })))}
        {...shared}
      />
    );
  }

  return (
    <div className={`stage ${params.get('tall') ? 'tall' : ''}`}>
      <aside className="controls">
        <h1>Maqueta CompraMejor</h1>
        <p>
          Prototipo navegable con datos de ejemplo. Las decisiones de diseño que aprobemos aquí se pasan a Flutter.
        </p>
        <label className="switch">
          <input type="checkbox" checked={worst} onChange={(e) => setWorst(e.target.checked)} />
          <span className="switch-track" aria-hidden="true" />
          Peor caso
        </label>
        <p className="controls-note">
          Agrega un producto sin foto, con un título enorme, un precio de cinco cifras y un precio sin verificar
          hace 3 días.
        </p>
        <p className="controls-note">Ábrelo en el celular con la dirección de red que muestra la terminal.</p>
      </aside>

      <div className="phone">
        <div className="screen">
          {screen}
          {!product && (
            <nav className="nav" aria-label="Principal">
              {TABS.map((t) => (
                <button
                  key={t.id}
                  className="nav-item"
                  aria-current={tab === t.id ? 'page' : undefined}
                  onClick={() => goTab(t.id)}
                >
                  <span className="nav-icon">
                    <Icon name={t.icon} size={22} filled={tab === t.id && t.icon === 'heart'} />
                    {t.id === 'alerts' && unread > 0 && <span className="nav-dot" />}
                  </span>
                  <span className="nav-label">{t.label}</span>
                </button>
              ))}
            </nav>
          )}
          {toast && (
            <div key={toast.key} className={`toast ${product ? 'toast-high' : ''}`} role="status">
              {toast.text}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
