// Datos de ejemplo para la maqueta. Basados en productos reales del catálogo,
// pero precios, historiales y disponibilidad son inventados.

// logo: ícono cuadrado publicado por cada tienda (public/stores). Sin logo usable se muestran
// las iniciales con el color de la tienda.
export const STORES = {
  coolbox: { name: 'Coolbox', short: 'CB', color: '#E11937', logo: '/stores/coolbox.png' },
  plazavea: { name: 'Plaza Vea', short: 'PV', color: '#E52421', logo: '/stores/plazavea.png' },
  oechsle: { name: 'Oechsle', short: 'OE', color: '#F0304F', logo: '/stores/oechsle.png' },
  promart: { name: 'Promart', short: 'PM', color: '#F36F21', logo: '/stores/promart.png' },
  metro: { name: 'Metro', short: 'MT', color: '#E30613', logo: '/stores/metro.png' },
  efe: { name: 'Efe', short: 'EF', color: '#0072CE', logo: '/stores/efe.png' },
  lacuracao: { name: 'La Curacao', short: 'LC', color: '#111111', logo: '/stores/lacuracao.png' },
  memorykings: { name: 'Memory Kings', short: 'MK', color: '#15803D' },
  sercoplus: { name: 'SercoPlus', short: 'SP', color: '#C81E1E', logo: '/stores/sercoplus.ico' },
  infotec: { name: 'Infotec', short: 'IN', color: '#F25C05', logo: '/stores/infotec.ico' },
  phantom: { name: 'Phantom', short: 'PH', color: '#111111', logo: '/stores/phantom.ico' },
  estilos: { name: 'Estilos', short: 'ES', color: '#E3141B', logo: '/stores/estilos.ico' },
  shopstar: { name: 'Shopstar', short: 'SS', color: '#1BA6E8' },
};

export const CATEGORIES = [
  { slug: 'computo', name: 'Cómputo', icon: 'laptop', tone: 'lav', image: '/img/cat-computo.jpg' },
  { slug: 'celulares', name: 'Celulares', icon: 'phone', tone: 'pink', image: '/img/cat-celulares.jpg' },
  { slug: 'monitores', name: 'Monitores', icon: 'monitor', tone: 'sky', image: '/img/cat-monitores.jpg' },
  { slug: 'audio', name: 'Audio', icon: 'headphones', tone: 'mint', image: '/img/cat-audio.jpg' },
  { slug: 'electro', name: 'Electrohogar', icon: 'fridge', tone: 'cream', image: '/img/cat-electro.jpg' },
  { slug: 'hogar', name: 'Hogar', icon: 'sofa', tone: 'lav', image: '/img/cat-hogar.jpg' },
  { slug: 'moda', name: 'Moda', icon: 'shirt', tone: 'pink', image: '/img/cat-moda.jpg' },
  { slug: 'deportes', name: 'Deportes', icon: 'ball', tone: 'mint', image: '/img/cat-deportes.jpg' },
];

export const POPULAR_SEARCHES = ['Monitor 144 Hz', 'Refrigeradora', 'Audífonos Bluetooth', 'Laptop i5', 'SSD 480 GB'];

export const AVAILABILITY = {
  available: 'Disponible',
  low: 'Últimas unidades',
  out: 'Agotado',
  preorder: 'Preventa',
};

// --- historial determinístico (mismo dibujo en cada recarga) ---
function rng(seed) {
  let a = seed;
  return () => {
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
function hash(s) {
  let h = 7;
  for (const c of s) h = (Math.imul(31, h) + c.charCodeAt(0)) | 0;
  return h;
}
function makeHistory(id, current, listPrev) {
  // Un «antes» muy alto suele ser precio de lista, no un precio que se haya cobrado:
  // no lo dibujamos en el historial.
  const prev = listPrev && listPrev <= current * 1.35 ? listPrev : null;
  const r = rng(hash(id));
  const out = [];
  let p = (prev ?? current) * (1.02 + r() * 0.05);
  for (let i = 90; i >= 0; i--) {
    if (i === 0) p = current;
    else if (i <= 2 && prev) p = prev;
    else {
      if (r() < 0.12) p *= 0.94 + r() * 0.14;
      p = Math.max(current * 0.96, Math.min(p, current * 1.35));
    }
    out.push({ day: -i, price: i === 0 ? current : Math.round(p) });
  }
  return out;
}

export function buildProduct(def) {
  const offers = def.offers
    .map((o) => ({ availability: 'available', shipping: null, hours: 2, prev: null, ...o }))
    .sort((a, b) => (a.availability === 'out') - (b.availability === 'out') || a.price - b.price);
  const inStock = offers.filter((o) => o.availability !== 'out');
  const best = inStock[0] ?? offers[0];
  const priciest = inStock[inStock.length - 1] ?? best;
  return {
    ...def,
    offers,
    best,
    priciest,
    stale: best.hours > 48,
    discount: best.prev ? Math.round((1 - best.price / best.prev) * 100) : 0,
    savings: priciest.price - best.price,
    history: makeHistory(def.id, best.price, best.prev),
  };
}

export const PRODUCTS = [
  {
    id: 'teros-te2417s',
    image: '/img/teros-te2417s.jpg',
    brand: 'Teros',
    shortName: 'Monitor Teros TE-2417S 23.8" IPS 144 Hz',
    title: 'Monitor plano Teros TE-2417S 23.8", IPS, Full HD 1920 x 1080, 144 Hz, 1 ms, HDMI, DisplayPort',
    category: 'monitores',
    kind: 'monitor',
    specs: [['Pantalla', '23.8" IPS'], ['Resolución', '1920 x 1080'], ['Frecuencia', '144 Hz'], ['Respuesta', '1 ms'], ['Entradas', 'HDMI, DisplayPort']],
    offers: [
      { store: 'coolbox', price: 269, prev: 329, hours: 2, shipping: 0 },
      { store: 'memorykings', price: 299, hours: 5, availability: 'low' },
      { store: 'sercoplus', price: 349, hours: 3, shipping: 15 },
      { store: 'phantom', price: 350, hours: 9 },
    ],
  },
  {
    id: 'msi-mp225',
    image: '/img/msi-mp225.jpg',
    brand: 'MSI',
    shortName: 'Monitor MSI PRO MP225 21.5" IPS 120 Hz',
    title: 'Monitor plano MSI PRO MP225 E12L 21.5", IPS, Full HD, 120 Hz, 1 ms, HDMI y VGA, negro',
    category: 'monitores',
    kind: 'monitor',
    specs: [['Pantalla', '21.5" IPS'], ['Resolución', '1920 x 1080'], ['Frecuencia', '120 Hz'], ['Entradas', 'HDMI, VGA']],
    offers: [
      { store: 'memorykings', price: 239, prev: 279, hours: 1 },
      { store: 'sercoplus', price: 255, hours: 4 },
      { store: 'infotec', price: 259, hours: 6, availability: 'out' },
    ],
  },
  {
    id: 'kingston-a400',
    image: '/img/kingston-a400.jpg',
    brand: 'Kingston',
    shortName: 'SSD Kingston A400 480 GB SATA 2.5"',
    title: 'Disco sólido SSD Kingston A400, 480GB, SATA 6 Gb/s, 2.5", 7 mm, negro',
    category: 'computo',
    kind: 'ssd',
    specs: [['Capacidad', '480 GB'], ['Formato', '2.5"'], ['Interfaz', 'SATA 3'], ['Lectura', 'hasta 500 MB/s']],
    offers: [
      { store: 'memorykings', price: 189, hours: 3 },
      { store: 'sercoplus', price: 199, hours: 3 },
      { store: 'infotec', price: 215, hours: 12 },
      { store: 'coolbox', price: 449, prev: 580, hours: 2 },
    ],
  },
  {
    id: 'zte-a35e',
    image: '/img/zte-a35e.png',
    brand: 'ZTE',
    shortName: 'Celular ZTE Blade A35e 64 GB',
    title: 'Celular ZTE Blade A35e 64GB, 2GB RAM, cámara trasera 8MP y frontal 5MP, 6.52" gris',
    category: 'celulares',
    kind: 'phone',
    specs: [['Almacenamiento', '64 GB'], ['RAM', '2 GB'], ['Pantalla', '6.52"'], ['Cámaras', '8 MP + 5 MP']],
    offers: [
      { store: 'coolbox', price: 339, prev: 399, hours: 1 },
      { store: 'shopstar', price: 349, hours: 7 },
      { store: 'metro', price: 369, hours: 2 },
    ],
  },
  {
    id: 'lenovo-slim3',
    image: '/img/lenovo-slim3.jpg',
    brand: 'Lenovo',
    shortName: 'Laptop Lenovo IdeaPad Slim 3 14" OLED Core i5',
    title: 'Laptop Lenovo IdeaPad Slim 3 14IRH10 14" WUXGA OLED, Intel Core i5-13420H, 16GB RAM, SSD 512GB, luna grey',
    category: 'computo',
    kind: 'laptop',
    specs: [['Procesador', 'Core i5-13420H'], ['RAM', '16 GB'], ['Almacenamiento', '512 GB SSD'], ['Pantalla', '14" WUXGA OLED']],
    offers: [
      { store: 'coolbox', price: 2819, prev: 4139, hours: 3 },
      { store: 'oechsle', price: 2899, hours: 5 },
      { store: 'shopstar', price: 2949, hours: 20 },
      { store: 'efe', price: 2999, hours: 4 },
      { store: 'lacuracao', price: 3099, hours: 2 },
    ],
  },
  {
    id: 'sony-whch520',
    image: '/img/sony-whch520.jpg',
    brand: 'Sony',
    shortName: 'Audífonos Sony WH-CH520 Bluetooth',
    title: 'Audífonos inalámbricos Sony WH-CH520, Bluetooth, hasta 50 h de batería, negro',
    category: 'audio',
    kind: 'headphones',
    specs: [['Conexión', 'Bluetooth 5.2'], ['Batería', 'hasta 50 h'], ['Micrófono', 'Sí']],
    offers: [
      { store: 'coolbox', price: 129, prev: 219, hours: 1 },
      { store: 'estilos', price: 149, hours: 2 },
      { store: 'oechsle', price: 159, hours: 6 },
      { store: 'metro', price: 169, hours: 3 },
    ],
  },
  {
    id: 'nokia-105',
    image: '/img/nokia-105.jpg',
    brand: 'Nokia',
    shortName: 'Celular Nokia 105 4G Dual SIM',
    title: 'Celular Nokia 105 4G TA-1659, 128 MB, 48 MB RAM, Dual SIM, batería de 1450 mAh, negro',
    category: 'celulares',
    kind: 'phone',
    specs: [['Red', '4G'], ['SIM', 'Dual SIM'], ['Batería', '1450 mAh']],
    offers: [
      { store: 'metro', price: 139, hours: 2 },
      { store: 'coolbox', price: 149, hours: 1 },
      { store: 'estilos', price: 159, hours: 30 },
    ],
  },
  {
    id: 'teros-te2415',
    image: '/img/teros-te2415.jpg',
    brand: 'Teros',
    shortName: 'Monitor Teros TE-2415 23.8" IPS 120 Hz',
    title: 'Monitor plano 23.8" Teros TE-2415 Panel IPS, FHD (1920 x 1080), 120 Hz, 1ms, HDMI / DisplayPort',
    category: 'monitores',
    kind: 'monitor',
    specs: [['Pantalla', '23.8" IPS'], ['Frecuencia', '120 Hz'], ['Entradas', 'HDMI, DisplayPort']],
    offers: [
      { store: 'coolbox', price: 269, prev: 299, hours: 4 },
      { store: 'infotec', price: 284, hours: 6 },
    ],
  },
  {
    id: 'arzopa-a1pro',
    image: '/img/arzopa-a1pro.png',
    brand: 'Arzopa',
    shortName: 'Monitor portátil Arzopa Z1RC 16" 2.5K',
    title: 'Monitor portátil Arzopa Z1RC 16" IPS 2.5K 2560x1600, 60Hz, 5ms, Mini HDMI, USB Tipo-C + funda',
    category: 'monitores',
    kind: 'monitor',
    specs: [['Pantalla', '16" IPS 2.5K'], ['Conexión', 'USB-C, Mini HDMI'], ['Incluye', 'Funda']],
    offers: [{ store: 'coolbox', price: 589, prev: 699, hours: 8 }],
  },
  {
    id: 'blackline-refri-417',
    image: '/img/refri.jpg',
    brand: 'Blackline',
    shortName: 'Refrigeradora Blackline 417 L No Frost inverter',
    title: 'Refrigeradora BLACKLINE 417L No Frost TM 417L BI-INV, negro inox',
    category: 'electro',
    kind: null,
    specs: [['Capacidad', '417 L'], ['Tecnología', 'No Frost, inverter'], ['Color', 'Negro inox']],
    offers: [
      { store: 'plazavea', price: 1299, prev: 2699, hours: 2, shipping: 0 },
      { store: 'oechsle', price: 1399, hours: 4 },
      { store: 'promart', price: 1449, hours: 6, availability: 'low' },
      { store: 'efe', price: 1499, hours: 3, shipping: 49 },
      { store: 'lacuracao', price: 1549, hours: 5 },
    ],
  },
  {
    id: 'blackline-airfryer-10',
    image: '/img/airfryer.jpg',
    brand: 'Blackline',
    shortName: 'Freidora de aire Blackline 10 L',
    title: 'Freidora de Aire BLACKLINE 10L con doble canasta y panel digital',
    category: 'electro',
    kind: null,
    specs: [['Capacidad', '10 L'], ['Panel', 'Digital']],
    offers: [
      { store: 'plazavea', price: 269, prev: 279, hours: 1 },
      { store: 'metro', price: 279, hours: 2 },
      { store: 'promart', price: 299, hours: 8 },
    ],
  },
].map(buildProduct);

// Producto con datos extremos para probar la interfaz («Peor caso»).
export const WORST_CASE = buildProduct({
  id: 'worst',
  brand: 'Corporación Importadora Internacional de Electrodomésticos del Perú',
  shortName:
    'Refrigeradora Side by Side No Frost Inverter 601 litros con dispensador de agua y hielo, panel táctil y acabado acero inoxidable RS60T5200S9/PE',
  title:
    'Refrigeradora Side by Side No Frost Inverter 601 litros con dispensador de agua y hielo, panel táctil, acabado acero inoxidable, modelo RS60T5200S9/PE edición especial 2026 con garantía extendida',
  category: 'electro',
  kind: null,
  specs: [],
  offers: [{ store: 'infotec', price: 12999.9, hours: 70 }],
});

export const INITIAL_FEED = [
  { id: 'f1', productId: 'teros-te2417s', type: 'drop', title: 'Bajó 18% en Coolbox', body: 'Ahora cuesta S/ 269.00. Antes S/ 329.00.', when: 'hace 2 h', unread: true },
  { id: 'f2', productId: 'kingston-a400', type: 'stores', title: 'Ahora lo comparamos en 4 tiendas', body: 'Se sumó Coolbox. El más barato sigue en Memory Kings.', when: 'hace 1 día', unread: true },
  { id: 'f3', productId: 'zte-a35e', type: 'drop', title: 'Bajó 15% en Coolbox', body: 'Ahora cuesta S/ 339.00. Antes S/ 399.00.', when: 'hace 3 días', unread: false },
  { id: 'f4', productId: 'msi-mp225', type: 'stock', title: 'Se agotó en Infotec', body: 'Sigue disponible en Memory Kings y SercoPlus.', when: 'hace 5 días', unread: false },
];

export const soles = (n) =>
  'S/ ' + n.toLocaleString('es-PE', { minimumFractionDigits: 2, maximumFractionDigits: 2 });

export const ago = (hours) => {
  if (hours < 1) return 'hace menos de 1 h';
  if (hours < 24) return `hace ${hours} h`;
  const d = Math.round(hours / 24);
  return `hace ${d} ${d === 1 ? 'día' : 'días'}`;
};

export const normalize = (s) =>
  s.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');
