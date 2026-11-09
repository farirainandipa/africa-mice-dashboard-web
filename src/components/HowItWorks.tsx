import { HOW_IT_WORKS } from '../content';
import Reveal from './Reveal';
import SectionHeading from './SectionHeading';

/** How it works: three high-level steps in a horizontal strip (stacked on mobile). */
export default function HowItWorks() {
  return (
    <section id="how-it-works" aria-labelledby="how-heading" className="border-t border-line py-20 sm:py-28">
      <div className="mx-auto max-w-6xl px-5 sm:px-8">
        <SectionHeading id="how-heading" overline={HOW_IT_WORKS.overline} heading={HOW_IT_WORKS.heading} />

        <ol className="relative mt-14 grid gap-10 md:grid-cols-3 md:gap-8">
          {/* Connecting rule behind the step markers (desktop only) */}
          <span aria-hidden="true" className="absolute left-5 right-5 top-5 hidden h-px bg-line md:block" />

          {HOW_IT_WORKS.steps.map((step, i) => (
            <li key={step.title} className="relative">
              <Reveal delay={i * 120}>
                <span className="relative flex h-10 w-10 items-center justify-center rounded-full border border-accent/50 bg-navy text-sm font-bold text-accent">
                  {String(i + 1).padStart(2, '0')}
                </span>
                <h3 className="mt-6 text-lg font-semibold tracking-tight text-ink">{step.title}</h3>
                <p className="mt-2 max-w-xs text-[15px] leading-relaxed text-muted">{step.body}</p>
              </Reveal>
            </li>
          ))}
        </ol>
      </div>
    </section>
  );
}
