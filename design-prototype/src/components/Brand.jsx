import { STORES } from '../data.js';

export function Logo() {
  return (
    <span className="logo" aria-label="CompraMejor">
      <svg viewBox="0 0 36 36" width="34" height="34" aria-hidden="true">
        <defs>
          <linearGradient id="logo-bag" x1="0" y1="0" x2="1" y2="1">
            <stop offset="0" stopColor="#2563EB" />
            <stop offset="1" stopColor="#0B1F4D" />
          </linearGradient>
        </defs>
        <path d="M13 12V9.5a5 5 0 0 1 10 0V12" fill="none" stroke="#0B1F4D" strokeWidth="2.4" strokeLinecap="round" />
        <path d="M8 12h20l-1.8 17.5a2 2 0 0 1-2 1.8H11.8a2 2 0 0 1-2-1.8z" fill="url(#logo-bag)" />
        <text x="18" y="25.5" textAnchor="middle" fontSize="10" fontWeight="700" fill="#fff" fontFamily="Poppins">%</text>
        <path d="M3 27c9 6 23 4 30-9" fill="none" stroke="#E11D8E" strokeWidth="3" strokeLinecap="round" />
      </svg>
      <span className="logo-word">
        Compra<span>Mejor</span>
      </span>
    </span>
  );
}

export function StoreBadge({ code, size = 28 }) {
  const s = STORES[code];
  if (s.logo) {
    return (
      <span className="store-badge store-badge-logo" style={{ width: size, height: size }} title={s.name} aria-hidden="true">
        <img src={s.logo} alt="" />
      </span>
    );
  }
  return (
    <span
      className="store-badge"
      style={{ '--c': s.color, width: size, height: size, fontSize: Math.round(size * 0.36) }}
      title={s.name}
      aria-hidden="true"
    >
      {s.short}
    </span>
  );
}
