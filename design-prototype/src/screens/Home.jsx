import { useState } from 'react';
import { CATEGORIES, STORES, soles } from '../data.js';
import { Logo, StoreBadge } from '../components/Brand.jsx';
import Icon from '../components/Icon.jsx';
import ProductArt from '../components/ProductArt.jsx';
import ProductCard from '../components/ProductCard.jsx';

export default function Home({ products, open, goSearch, goAlerts, unread, recent, saved, toggleSave }) {
  const drops = products.filter((p) => p.discount > 0 && !p.stale).sort((a, b) => b.discount - a.discount);
  const [slide, setSlide] = useState(0);
  const [cat, setCat] = useState('todo');
  const usedCats = CATEGORIES.filter((c) => products.some((p) => p.category === c.slug));
  const seen = recent.map((id) => products.find((p) => p.id === id)).filter(Boolean);
  const grid = cat === 'todo' ? products : products.filter((p) => p.category === cat);

  return (
    <main className="view">
      <header className="home-top">
        <Logo />
        <button className="icon-btn has-dot" aria-label={`Alertas, ${unread} sin leer`} onClick={goAlerts}>
          <Icon name="bell" />
          {unread > 0 && <span className="dot">{unread}</span>}
        </button>
      </header>

      <h1 className="home-title">¿Qué quieres comparar hoy?</h1>
      <div className="search-field">
        <button className="search-field-main" onClick={() => goSearch()}>
          <Icon name="search" size={20} />
          <span>Busca producto, marca o código</span>
        </button>
        <button className="search-scan" aria-label="Escanear código de barras" onClick={() => goSearch({ scan: true })}>
          <Icon name="scan" size={20} />
        </button>
      </div>

      {drops.length > 0 && (
        <section className="hero" aria-label="Bajaron de precio">
          <div
            className="hero-track"
            onScroll={(e) => {
              const el = e.currentTarget;
              setSlide(Math.round(el.scrollLeft / (el.clientWidth - 32 + 12)));
            }}
          >
            {drops.slice(0, 3).map((p) => (
              <article key={p.id} className="hero-card" onClick={() => open(p.id)}>
                <div className="hero-copy">
                  <span className="drop-pill">
                    <Icon name="down" size={14} stroke={2.4} /> Bajó {p.discount}%
                  </span>
                  <h2>{p.shortName}</h2>
                  <p className="hero-price">
                    <strong>{soles(p.best.price)}</strong>
                    <s>{soles(p.best.prev)}</s>
                  </p>
                  <p className="hero-store">
                    en {STORES[p.best.store].name}
                    {p.offers.length > 1 && `, comparado en ${p.offers.length} tiendas`}
                  </p>
                </div>
                <div className={`hero-art ${p.image ? 'has-photo' : ''}`}>
                  <ProductArt image={p.image} kind={p.kind} dark />
                </div>
              </article>
            ))}
          </div>
          <div className="dots" aria-hidden="true">
            {drops.slice(0, 3).map((p, i) => (
              <span key={p.id} className={i === slide ? 'is-on' : ''} />
            ))}
          </div>
        </section>
      )}

      {seen.length > 0 && (
        <section className="sec">
          <div className="sec-head">
            <h2>Vistos recientemente</h2>
          </div>
          <div className="mini-strip">
            {seen.map((p) => (
              <button key={p.id} className="mini" onClick={() => open(p.id)}>
                <span className="mini-art">
                  <ProductArt image={p.image} kind={p.kind} />
                </span>
                <span className="mini-title">{p.shortName}</span>
                <span className="mini-price">{p.stale ? 'Por confirmar' : soles(p.best.price)}</span>
              </button>
            ))}
          </div>
        </section>
      )}

      <section className="sec">
        <div className="sec-head">
          <h2>Tiendas que comparamos</h2>
        </div>
        <div className="store-strip">
          {Object.entries(STORES).map(([code, s]) => (
            <button key={code} className="store-tile" onClick={() => goSearch({ store: code })}>
              <StoreBadge code={code} size={48} />
              <span>{s.name}</span>
            </button>
          ))}
        </div>
      </section>

      <section className="sec">
        <div className="sec-head">
          <h2>Categorías</h2>
        </div>
        <div className="cat-grid">
          {CATEGORIES.map((c) => (
            <button key={c.slug} className="cat-tile" onClick={() => goSearch({ category: c.slug })}>
              <span className={`cat-icon tone-${c.tone}`}>
                <img src={c.image} alt="" loading="lazy" />
              </span>
              <span>{c.name}</span>
            </button>
          ))}
        </div>
      </section>

      <section className="sec">
        <div className="sec-head">
          <h2>Mejores precios de hoy</h2>
          <button className="link" onClick={() => goSearch()}>
            Ver todo
          </button>
        </div>
        <div className="chip-row chip-scroll">
          <button className="chip" aria-pressed={cat === 'todo'} onClick={() => setCat('todo')}>
            Todo
          </button>
          {usedCats.map((c) => (
            <button key={c.slug} className="chip" aria-pressed={cat === c.slug} onClick={() => setCat(c.slug)}>
              {c.name}
            </button>
          ))}
        </div>
        <div className="grid">
          {grid.map((p) => (
            <ProductCard key={p.id} p={p} open={open} saved={saved} toggleSave={toggleSave} />
          ))}
        </div>
      </section>
    </main>
  );
}
