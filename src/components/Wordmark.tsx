import { BRAND } from '../content';

/** Dot pattern for the small mark: [cx, cy, opacity]. */
const MARK_DOTS: [number, number, number][] = [
  [7, 7, 1], [12, 7, 0.4], [17, 7, 0.4],
  [7, 12, 0.4], [12, 12, 1], [17, 12, 0.4],
  [12, 17, 0.4], [17, 17, 1],
];

/** Small dot-grid mark plus the product name. */
export default function Wordmark({ className = '' }: { className?: string }) {
  return (
    <span className={`inline-flex items-center gap-2.5 ${className}`}>
      <svg viewBox="0 0 24 24" className="h-7 w-7 shrink-0" aria-hidden="true">
        <rect x="0.5" y="0.5" width="23" height="23" rx="6" fill="#121A2B" stroke="rgba(255,255,255,0.12)" />
        {MARK_DOTS.map(([cx, cy, o]) => (
          <circle key={`${cx}-${cy}`} cx={cx} cy={cy} r="1.6" fill="#19C3B1" opacity={o} />
        ))}
      </svg>
      <span className="text-[15px] font-bold tracking-tight text-ink">{BRAND.name}</span>
    </span>
  );
}
