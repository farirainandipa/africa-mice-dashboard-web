import { ArrowRight } from 'lucide-react';
import { AUDIENCE } from '../content';
import { ICONS } from './icons';
import Reveal from './Reveal';
import SectionHeading from './SectionHeading';

/** Who it's for: three audience columns; event owners get a link to the "Submit an event" form. */
export default function Audience() {
  return (
    <section id="audience" aria-labelledby="audience-heading" className="border-t border-line bg-panel/40 py-20 sm:py-28">
      <div className="mx-auto max-w-6xl px-5 sm:px-8">
        <SectionHeading id="audience-heading" overline={AUDIENCE.overline} heading={AUDIENCE.heading} />

        <div className="mt-14 grid overflow-hidden rounded-xl border border-line md:grid-cols-3">
          {AUDIENCE.groups.map((group, i) => {
            const Icon = ICONS[group.icon];
            const cta = 'cta' in group ? group.cta : undefined;
            return (
              <Reveal
                key={group.title}
                delay={i * 100}
                className={`flex flex-col bg-navy p-7 sm:p-8 ${i > 0 ? 'border-t border-line md:border-l md:border-t-0' : ''}`}
              >
                <Icon size={22} className="text-accent" aria-hidden="true" />
                <h3 className="mt-6 text-xl font-semibold tracking-tight text-ink">{group.title}</h3>
                <p className="mt-3 flex-1 text-[15px] leading-relaxed text-muted">{group.body}</p>
                {cta && (
                  <a
                    href={cta.href}
                    className="group mt-7 inline-flex items-center gap-2 self-start text-sm font-semibold text-accent transition-colors hover:text-accent-strong"
                  >
                    {cta.label}
                    <ArrowRight size={15} className="transition-transform group-hover:translate-x-0.5" aria-hidden="true" />
                  </a>
                )}
              </Reveal>
            );
          })}
        </div>
      </div>
    </section>
  );
}
