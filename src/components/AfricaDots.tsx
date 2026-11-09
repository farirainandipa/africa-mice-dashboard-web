import { useMemo } from 'react';

/**
 * Decorative dotted outline of the African continent.
 *
 * A simplified coastline (longitude/latitude) is used as a mask: a regular
 * point grid is sampled and only points inside the outline are drawn.
 * A handful of accent points with a soft pulse suggest destinations.
 */

type LonLat = [number, number];

// Simplified mainland outline, clockwise from the Strait of Gibraltar.
const MAINLAND: LonLat[] = [
  [-6, 35.9], [-1, 35.3], [3, 36.8], [10, 37.2], [11, 33.5], [15, 32.3], [19.5, 30.3], [20, 32.4],
  [25, 31.8], [32, 31.3], [34.3, 29.5], [35, 24], [37.4, 18.6], [39.6, 15.4], [43.3, 12.5],
  [44.5, 10.5], [51.2, 11.8], [51, 10.3], [49, 6], [46, 2], [42, -1], [40, -3.6], [39.3, -6.8],
  [40.5, -10.5], [40.6, -15], [37, -17.5], [35.3, -22], [35.5, -24], [32.8, -26], [32.5, -28.6],
  [30.5, -31], [27.5, -33.5], [25, -34], [20, -34.8], [18.4, -34.3], [18, -32], [16.5, -28.6],
  [15, -26], [14.5, -23], [12, -18], [11.8, -15.5], [13.5, -12], [13, -9], [12.2, -6], [9.5, -2],
  [9.5, 1], [9.7, 4], [8.5, 4.5], [6, 4.3], [3, 6.4], [-2, 4.8], [-7.5, 4.4], [-11, 6.8],
  [-13.3, 8.5], [-15, 11], [-17.2, 14.7], [-16.5, 19.5], [-17, 21], [-13, 27.5], [-9.8, 29.5],
  [-9.5, 32.5], [-6.8, 34],
];

const MADAGASCAR: LonLat[] = [
  [49.3, -12], [50.5, -15.5], [49.5, -17], [47.2, -25], [45, -25.5], [43.3, -22], [44.4, -16.5], [47, -14.5],
];

// Illustrative destination points (no meaning beyond decoration).
const HIGHLIGHTS: LonLat[] = [
  [-7.6, 31.6], [31.2, 30], [-0.2, 5.6], [36.8, -1.3], [30.1, -2], [25.8, -17.9], [18.4, -33.9], [3.4, 6.5],
];

const LON_MIN = -18;
const LAT_MAX = 38;
const STEP = 1.5;

/** Project lon/lat into SVG space (simple equirectangular, y flipped). */
const project = ([lon, lat]: LonLat): [number, number] => [lon - LON_MIN, LAT_MAX - lat];

/** Ray-casting point-in-polygon test. */
function inside([x, y]: LonLat, poly: LonLat[]): boolean {
  let hit = false;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const [xi, yi] = poly[i];
    const [xj, yj] = poly[j];
    if (yi > y !== yj > y && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) hit = !hit;
  }
  return hit;
}

export default function AfricaDots({ className = '' }: { className?: string }) {
  const dots = useMemo(() => {
    const points: [number, number][] = [];
    for (let lat = LAT_MAX; lat >= -36; lat -= STEP) {
      for (let lon = LON_MIN; lon <= 53; lon += STEP) {
        const p: LonLat = [lon, lat];
        if (inside(p, MAINLAND) || inside(p, MADAGASCAR)) points.push(project(p));
      }
    }
    return points;
  }, []);

  return (
    <svg viewBox="-1 -1 73 76" className={className} aria-hidden="true" focusable="false">
      <defs>
        <radialGradient id="africa-glow" cx="50%" cy="50%" r="50%">
          <stop offset="0%" stopColor="#19C3B1" stopOpacity="0.9" />
          <stop offset="100%" stopColor="#19C3B1" stopOpacity="0" />
        </radialGradient>
      </defs>

      <g fill="#E8ECF3" opacity="0.38">
        {dots.map(([x, y]) => (
          <circle key={`${x}-${y}`} cx={x} cy={y} r="0.28" />
        ))}
      </g>

      {HIGHLIGHTS.map((pt, i) => {
        const [x, y] = project(pt);
        return (
          <g key={i}>
            <circle cx={x} cy={y} r="2.2" fill="url(#africa-glow)" opacity="0.35" />
            <circle
              className="pulse-ring"
              cx={x}
              cy={y}
              r="0.6"
              fill="none"
              stroke="#19C3B1"
              strokeWidth="0.15"
              style={{ animationDelay: `${i * 0.4}s` }}
            />
            <circle cx={x} cy={y} r="0.5" fill="#19C3B1" />
          </g>
        );
      })}
    </svg>
  );
}
