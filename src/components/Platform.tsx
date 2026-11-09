import { PLATFORM } from '../content';
import { ICONS } from './icons';
import Reveal from './Reveal';
import SectionHeading from './SectionHeading';

/** Platform: outcome-focused feature cards. */
export default function Platform() {
  return (
    <section id="platform" aria-labelledby="platform-heading" className="border-t border-line py-20 sm:py-28">
      <div className="mx-auto max-w-6xl px-5 sm:px-8">
        <SectionHeading
          id="platform-heading"
          overline={PLATFORM.overline}
          heading={PLATFORM.heading}
          intro={PLATFORM.intro}
        />

        <ul className="mt-14 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          {PLATFORM.features.map((feature, i) => {
            const Icon = ICONS[feature.icon];
            return (
              <li key={feature.title}>
                <Reveal delay={i * 80} className="h-full">
                  <article className="group flex h-full flex-col rounded-xl border border-line bg-panel p-6 transition-colors duration-300 hover:border-accent/40 hover:bg-panel-2">
                    <span className="flex h-10 w-10 items-center justify-center rounded-lg border border-line bg-navy text-accent transition-colors group-hover:border-accent/40">
                      <Icon size={18} aria-hidden="true" />
                    </span>
                    <h3 className="mt-6 text-lg font-semibold tracking-tight text-ink">{feature.title}</h3>
                    <p className="mt-2 text-[15px] leading-relaxed text-muted">{feature.body}</p>
                  </article>
                </Reveal>
              </li>
            );
          })}
        </ul>
      </div>
    </section>
  );
}
