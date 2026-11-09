import { ArrowRight } from 'lucide-react';
import { CONTRIBUTE } from '../content';
import { ICONS } from './icons';
import Reveal from './Reveal';
import SectionHeading from './SectionHeading';

/** Two cards linking to the public pipeline forms (event submission and destination partner data). */
export default function Contribute() {
  return (
    <section id="contribute" aria-labelledby="contribute-heading" className="border-t border-line bg-panel/40 py-20 sm:py-24">
      <div className="mx-auto max-w-6xl px-5 sm:px-8">
        <SectionHeading
          id="contribute-heading"
          overline={CONTRIBUTE.overline}
          heading={CONTRIBUTE.heading}
          intro={CONTRIBUTE.intro}
        />

        <div className="mt-14 grid gap-5 md:grid-cols-2">
          {CONTRIBUTE.cards.map((card, i) => {
            const Icon = ICONS[card.icon];
            return (
              <Reveal
                key={card.title}
                delay={i * 100}
                className="flex flex-col rounded-xl border border-line bg-navy p-7 sm:p-8"
              >
                <Icon size={22} className="text-accent" aria-hidden="true" />
                <h3 className="mt-6 text-xl font-semibold tracking-tight text-ink">{card.title}</h3>
                <p className="mt-3 flex-1 text-[15px] leading-relaxed text-muted">{card.body}</p>
                <a
                  href={card.cta.href}
                  className="group mt-7 inline-flex items-center gap-2 self-start text-sm font-semibold text-accent transition-colors hover:text-accent-strong"
                >
                  {card.cta.label}
                  <ArrowRight size={15} className="transition-transform group-hover:translate-x-0.5" aria-hidden="true" />
                </a>
              </Reveal>
            );
          })}
        </div>
      </div>
    </section>
  );
}
