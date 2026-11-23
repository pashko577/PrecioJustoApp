import { useState } from 'react';
import { soles } from '../data.js';

const W = 320;
const H = 120;
const PAD = 8;

export default function PriceChart({ history, stale = false }) {
  const [range, setRange] = useState(30);
  const data = history.slice(-(range + 1));
  const prices = data.map((d) => d.price);
  const min = Math.min(...prices);
  const max = Math.max(...prices);
  const cur = prices[prices.length - 1];

  const x = (i) => PAD + (i * (W - 2 * PAD)) / (data.length - 1);
  const y = (v) => (max === min ? H / 2 : PAD + ((max - v) * (H - 2 * PAD)) / (max - min));
  const line = data.map((d, i) => `${i ? 'L' : 'M'}${x(i).toFixed(1)},${y(d.price).toFixed(1)}`).join('');
  const area = `${line}L${x(data.length - 1)},${H}L${x(0)},${H}Z`;
  const minIdx = prices.lastIndexOf(min);

  let verdict;
  if (stale) verdict = { tone: 'wait', text: 'No podemos confirmar el precio de hoy. Revisa en la tienda.' };
  else if (cur <= min) verdict = { tone: 'good', text: `Es el precio más bajo de los últimos ${range} días.` };
  else if (cur <= min + (max - min) * 0.25)
    verdict = { tone: 'good', text: `Está cerca del mínimo de los últimos ${range} días.` };
  else verdict = { tone: 'wait', text: `Estuvo más barato (${soles(min)}). Crea una alerta y te avisamos.` };

  return (
    <div className="chart">
      <div className="seg" role="group" aria-label="Periodo">
        {[30, 90].map((r) => (
          <button key={r} aria-pressed={range === r} onClick={() => setRange(r)}>
            {r} días
          </button>
        ))}
      </div>
      <p className={`verdict verdict-${verdict.tone}`}>{verdict.text}</p>
      <svg
        className="chart-svg"
        viewBox={`0 0 ${W} ${H}`}
        role="img"
        aria-label={`Precio entre ${soles(min)} y ${soles(max)} en los últimos ${range} días`}
      >
        <defs>
          <linearGradient id="chart-area" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0" stopColor="#2563EB" stopOpacity="0.18" />
            <stop offset="1" stopColor="#2563EB" stopOpacity="0" />
          </linearGradient>
        </defs>
        <path d={area} fill="url(#chart-area)" />
        <path d={line} fill="none" stroke="#2563EB" strokeWidth="2" strokeLinejoin="round" />
        <circle cx={x(minIdx)} cy={y(min)} r="4.5" fill="#14B8A6" stroke="#fff" strokeWidth="2" />
        <circle cx={x(data.length - 1)} cy={y(cur)} r="5" fill="#0B1F4D" stroke="#fff" strokeWidth="2" />
      </svg>
      <div className="chart-axis">
        <span>hace {range} días</span>
        <span>hoy</span>
      </div>
      <dl className="chart-stats">
        <div>
          <dt>Mínimo</dt>
          <dd className="is-min">{soles(min)}</dd>
        </div>
        <div>
          <dt>Máximo</dt>
          <dd>{soles(max)}</dd>
        </div>
        <div>
          <dt>Hoy</dt>
          <dd>{soles(cur)}</dd>
        </div>
      </dl>
    </div>
  );
}
