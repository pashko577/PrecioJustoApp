import { STORES } from '../data.js';
import { StoreBadge } from '../components/Brand.jsx';
import Icon from '../components/Icon.jsx';

function Toggle({ label, hint, on, onChange }) {
  return (
    <label className="pref-row">
      <span className="pref-text">
        <span className="pref-label">{label}</span>
        {hint && <span className="pref-hint">{hint}</span>}
      </span>
      <input type="checkbox" className="toggle" checked={on} onChange={(e) => onChange(e.target.checked)} />
    </label>
  );
}

export default function Profile({ prefs, setPrefs, hiddenStores, toggleStoreVisible, notify }) {
  const set = (k) => (v) => setPrefs({ ...prefs, [k]: v });
  const visible = Object.keys(STORES).length - hiddenStores.size;

  return (
    <main className="view">
      <h1 className="screen-title">Perfil</h1>

      <section className="login-card">
        <span className="login-avatar">
          <Icon name="user" size={26} />
        </span>
        <div>
          <h2>Guarda tus alertas en tu cuenta</h2>
          <p>Así no las pierdes si cambias de celular.</p>
        </div>
        <button className="btn btn-primary btn-block" onClick={() => notify('Aquí va el inicio de sesión')}>
          Iniciar sesión
        </button>
      </section>

      <section className="block">
        <h2>Notificaciones</h2>
        <div className="pref-group">
          <Toggle
            label="Bajadas de precio"
            hint="Cuando un producto guardado llega a tu precio"
            on={prefs.drops}
            onChange={set('drops')}
          />
          <Toggle label="Vuelve a tener stock" on={prefs.stock} onChange={set('stock')} />
          <Toggle label="Resumen semanal de ofertas" on={prefs.weekly} onChange={set('weekly')} />
        </div>
      </section>

      <section className="block">
        <div className="block-head">
          <h2>Tiendas que comparo</h2>
          <span className="block-count">
            {visible} de {Object.keys(STORES).length}
          </span>
        </div>
        <p className="block-hint">Desactiva las tiendas donde no compras y no las verás en los resultados.</p>
        <div className="pref-group">
          {Object.entries(STORES).map(([code, s]) => (
            <label key={code} className="pref-row">
              <span className="pref-store">
                <StoreBadge code={code} size={32} />
                <span className="pref-label">{s.name}</span>
              </span>
              <input
                type="checkbox"
                className="toggle"
                checked={!hiddenStores.has(code)}
                onChange={() => toggleStoreVisible(code)}
              />
            </label>
          ))}
        </div>
      </section>

      <section className="block">
        <h2>Ayuda</h2>
        <div className="pref-group">
          {['Cómo verificamos los precios', 'Sugerir una tienda', 'Términos y privacidad'].map((t) => (
            <button key={t} className="pref-row pref-link" onClick={() => notify(`Se abriría «${t}»`)}>
              <span className="pref-label">{t}</span>
              <Icon name="back" size={18} className="flip" />
            </button>
          ))}
        </div>
      </section>
    </main>
  );
}
