import { useId, useState } from 'react';
import Icon from './Icon.jsx';

// Foto del producto (imageUrl de la tienda). Si no hay foto o no carga, se muestra una
// ilustración de la categoría o el aviso «Sin foto».
export default function ProductArt({ image, kind, dark = false }) {
  const id = 'art' + useId().replace(/[^a-zA-Z0-9_-]/g, '');
  const [broken, setBroken] = useState(false);
  const screen = `url(#${id})`;
  const body = dark ? '#E8EDFB' : '#0B1F4D';

  if (image && !broken) {
    return <img className="photo" src={image} alt="" loading="lazy" onError={() => setBroken(true)} />;
  }

  if (!kind) {
    return (
      <div className="art-missing">
        <Icon name="box" size={32} stroke={1.5} />
        <span>Sin foto</span>
      </div>
    );
  }

  return (
    <svg className="art" viewBox="0 0 120 90" aria-hidden="true">
      <defs>
        <linearGradient id={id} x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#60A5FA" />
          <stop offset="0.55" stopColor="#2563EB" />
          <stop offset="1" stopColor="#E11D8E" />
        </linearGradient>
      </defs>
      {kind === 'monitor' && (
        <>
          <rect x="18" y="10" width="84" height="54" rx="4" fill={body} />
          <rect x="22" y="14" width="76" height="46" rx="2" fill={screen} />
          <path d="M54 64h12l3 11H51z" fill={dark ? '#B8C4E6' : '#334155'} />
          <rect x="42" y="75" width="36" height="4" rx="2" fill={body} />
        </>
      )}
      {kind === 'phone' && (
        <>
          <rect x="42" y="6" width="36" height="78" rx="7" fill={body} />
          <rect x="45.5" y="12" width="29" height="66" rx="3.5" fill={screen} />
          <rect x="55" y="8.5" width="10" height="2" rx="1" fill={dark ? '#0B1F4D' : '#475569'} />
        </>
      )}
      {kind === 'ssd' && (
        <>
          <rect x="20" y="22" width="80" height="48" rx="5" fill={body} />
          <rect x="28" y="30" width="50" height="32" rx="3" fill={screen} />
          <circle cx="89" cy="32" r="2.5" fill={dark ? '#0B1F4D' : '#94A3B8'} />
          <circle cx="89" cy="60" r="2.5" fill={dark ? '#0B1F4D' : '#94A3B8'} />
        </>
      )}
      {kind === 'laptop' && (
        <>
          <rect x="24" y="12" width="72" height="48" rx="4" fill={body} />
          <rect x="28" y="16" width="64" height="40" rx="2" fill={screen} />
          <path d="M12 63h96l-6 9H18z" fill={dark ? '#B8C4E6' : '#94A3B8'} />
        </>
      )}
      {kind === 'headphones' && (
        <>
          <path d="M30 58V46a30 30 0 0 1 60 0v12" fill="none" stroke={body} strokeWidth="6" strokeLinecap="round" />
          <rect x="20" y="48" width="18" height="30" rx="8" fill={body} />
          <rect x="82" y="48" width="18" height="30" rx="8" fill={body} />
          <rect x="24" y="53" width="10" height="20" rx="5" fill={screen} />
          <rect x="86" y="53" width="10" height="20" rx="5" fill={screen} />
        </>
      )}
    </svg>
  );
}
