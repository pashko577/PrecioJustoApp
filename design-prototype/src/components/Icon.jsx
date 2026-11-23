const PATHS = {
  search: (<><circle cx="11" cy="11" r="7" /><path d="m20 20-3.5-3.5" /></>),
  heart: <path d="M12 20s-7.5-4.6-7.5-10.2A4.3 4.3 0 0 1 12 7.2a4.3 4.3 0 0 1 7.5 2.6C19.5 15.4 12 20 12 20z" />,
  bell: (<><path d="M6 16v-5a6 6 0 1 1 12 0v5l1.5 2h-15z" /><path d="M10 20.5a2 2 0 0 0 4 0" /></>),
  home: <path d="M4 10.5 12 4l8 6.5V20h-5.5v-5.5h-5V20H4z" />,
  scan: (<><path d="M4 8V5h3M17 5h3v3M20 16v3h-3M7 19H4v-3" /><path d="M8.5 9v6M11 9v6M13.5 9v6M16 9v6" /></>),
  back: <path d="M15 5 8 12l7 7" />,
  external: (<><path d="M14 4h6v6M20 4l-9 9" /><path d="M18 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h5" /></>),
  down: <path d="M12 5v14M6 13l6 6 6-6" />,
  close: <path d="M6 6l12 12M18 6 6 18" />,
  share: (<><circle cx="6" cy="12" r="2.5" /><circle cx="18" cy="6" r="2.5" /><circle cx="18" cy="18" r="2.5" /><path d="m8.2 10.8 7.6-3.6M8.2 13.2l7.6 3.6" /></>),
  user: (<><circle cx="12" cy="8" r="4" /><path d="M4.5 20a7.5 7.5 0 0 1 15 0" /></>),
  check: <path d="m5 12.5 4.5 4.5L19 7.5" />,
  store: (<><path d="M4 9 5.5 4h13L20 9" /><path d="M4 9a2.7 2.7 0 0 0 5.3 0 2.7 2.7 0 0 0 5.4 0A2.7 2.7 0 0 0 20 9" /><path d="M5 11v9h14v-9" /></>),
  layers: (<><path d="m12 4 8 4-8 4-8-4z" /><path d="m4 12 8 4 8-4M4 16l8 4 8-4" /></>),
  box: (<><path d="m12 3 8 4.5v9L12 21l-8-4.5v-9z" /><path d="m4 7.5 8 4.5 8-4.5M12 12v9" /></>),
  // categorías
  laptop: (<><rect x="5" y="5" width="14" height="10" rx="1.5" /><path d="M3 19h18" /></>),
  monitor: (<><rect x="3" y="4" width="18" height="12" rx="1.5" /><path d="M9 20h6M12 16v4" /></>),
  phone: (<><rect x="7" y="3" width="10" height="18" rx="2.5" /><path d="M11 18h2" /></>),
  headphones: (<><path d="M4 15v-3a8 8 0 0 1 16 0v3" /><rect x="3" y="14" width="4" height="6" rx="1.5" /><rect x="17" y="14" width="4" height="6" rx="1.5" /></>),
  fridge: (<><rect x="6" y="3" width="12" height="18" rx="2" /><path d="M6 10h12M9 6v2M9 13v3" /></>),
  sofa: (<><path d="M5 11V8a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2v3" /><path d="M3 13a2 2 0 0 1 4 0v2h10v-2a2 2 0 0 1 4 0v5H3zM6 18v2M18 18v2" /></>),
  shirt: <path d="m8 4-5 3 2 4 2-1v10h10V10l2 1 2-4-5-3a4 4 0 0 1-8 0z" />,
  ball: (<><circle cx="12" cy="12" r="8" /><path d="m12 8 3.5 2.5-1.3 4h-4.4l-1.3-4zM12 4v4M4.6 9.8l3.9.7M19.4 9.8l-3.9.7M7.3 18.5l2.5-4M16.7 18.5l-2.5-4" /></>),
};

export default function Icon({ name, size = 22, filled = false, stroke = 1.8, className }) {
  return (
    <svg
      className={className}
      viewBox="0 0 24 24"
      width={size}
      height={size}
      fill={filled ? 'currentColor' : 'none'}
      stroke="currentColor"
      strokeWidth={stroke}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      {PATHS[name]}
    </svg>
  );
}
