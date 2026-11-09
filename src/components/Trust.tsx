import { Quote } from 'lucide-react';
import { TRUST } from '../content';
import Reveal from './Reveal';

/** Trust strip with a credibility line, a placeholder logo row and a testimonial card. */
export default function Trust() {
  return (
    <section aria-labelledby="trust-heading" className="border-t border-line bg-panel/40 py-20 sm:py-24">
      <div className="mx-auto max-w-6xl px-5 sm:px-8">
        <Reveal className="text-center">
          <p className="text-xs font-semibold uppercase tracking-[0.22em] text-accent">{TRUST.overline}</p>
          <h2 id="trust-heading" className="mx-auto mt-4 max-w-2xl text-2xl font-bold tracking-tight text-ink sm:text-3xl">
            {TRUST.heading}
          </h2>
        </Reveal>

        {/* Placeholder logos. Replace entries in content.ts (or swap for <img> tags) */}
        <Reveal delay={100}>
          <ul className="mt-12 grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-6" aria-label="Partners and clients">
            {TRUST.logos.map((logo, i) => (
              <li
                key={i}
                className="flex h-16 items-center justify-center rounded-lg border border-line bg-white/[0.03] text-xs font-semibold uppercase tracking-[0.2em] text-faint"
              >
                {logo}
              </li>
            ))}
          </ul>
        </Reveal>

        <Reveal delay={200}>
          <figure className="mx-auto mt-14 max-w-3xl rounded-xl border border-line bg-navy p-7 sm:p-10">
            <Quote size={22} className="text-accent" aria-hidden="true" />
            <blockquote className="mt-5 text-lg leading-relaxed text-ink sm:text-xl">
              <p>{TRUST.testimonial.quote}</p>
            </blockquote>
            <figcaption className="mt-7 flex items-center gap-4">
              <span aria-hidden="true" className="h-10 w-10 rounded-full border border-line bg-panel-2" />
              <span>
                <span className="block text-sm font-semibold text-ink">{TRUST.testimonial.name}</span>
                <span className="block text-sm text-faint">{TRUST.testimonial.role}</span>
              </span>
            </figcaption>
          </figure>
        </Reveal>
      </div>
    </section>
  );
}
