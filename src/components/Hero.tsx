import { ArrowRight, ArrowUpRight } from 'lucide-react';
import { CTA, DASHBOARD_URL, HERO } from '../content';
import AfricaDots from './AfricaDots';
import Reveal from './Reveal';
import { ButtonLink } from './Button';

/** Hero: headline, CTAs, stat chips, and the dotted Africa backdrop. */
export default function Hero() {
  return (
    <section id="top" aria-labelledby="hero-heading" className="relative isolate -mt-16 overflow-hidden pt-16">
      {/* Decorative backdrop: soft glow + dotted continent */}
      <div aria-hidden="true" className="pointer-events-none absolute inset-0 -z-10">
        <div className="absolute -right-40 top-10 h-[36rem] w-[36rem] rounded-full bg-accent/10 blur-3xl" />
        <div className="relative mx-auto h-full max-w-7xl">
          <AfricaDots className="absolute right-[-45%] top-28 h-[540px] w-auto opacity-25 sm:right-[-15%] sm:h-[620px] sm:opacity-50 lg:right-[-3%] lg:top-24 lg:h-[700px] lg:opacity-75" />
        </div>
        {/* Fade the map out behind the copy so text stays legible */}
        <div className="absolute inset-0 bg-gradient-to-r from-navy from-20% via-navy/60 via-50% to-transparent to-80% lg:from-30% lg:via-navy/30 lg:via-50% lg:to-65%" />
        <div className="absolute inset-x-0 bottom-0 h-32 bg-gradient-to-t from-navy to-transparent" />
      </div>

      <div className="mx-auto max-w-6xl px-5 pb-20 pt-20 sm:px-8 sm:pb-28 sm:pt-28 lg:pb-32 lg:pt-36">
        <Reveal className="max-w-3xl">
          <p className="inline-flex items-center gap-2 rounded-full border border-line bg-panel/60 px-3 py-1.5 text-[11px] font-semibold uppercase tracking-[0.2em] text-muted">
            <span className="h-1.5 w-1.5 rounded-full bg-accent" aria-hidden="true" />
            {HERO.overline}
          </p>
          <h1
            id="hero-heading"
            className="mt-7 text-[2.5rem] font-extrabold leading-[1.05] tracking-tight text-ink sm:text-6xl lg:text-[4.25rem]"
          >
            {HERO.headline}
          </h1>
          <p className="mt-6 max-w-2xl text-base leading-relaxed text-muted sm:text-lg">{HERO.subhead}</p>

          <div className="mt-9 flex flex-col gap-3 sm:flex-row">
            <ButtonLink href="#access" className="px-6 py-3 text-[15px]">
              {CTA.requestAccess}
              <ArrowRight size={16} aria-hidden="true" />
            </ButtonLink>
            <ButtonLink
              variant="ghost"
              href={DASHBOARD_URL}
              className="px-6 py-3 text-[15px]"
            >
              {CTA.signIn}
              <ArrowUpRight size={16} aria-hidden="true" />
            </ButtonLink>
          </div>
        </Reveal>

        {/* Stat chips — figures are placeholders in content.ts */}
        <Reveal delay={150}>
          <dl className="mt-16 grid max-w-3xl grid-cols-3 divide-x divide-line overflow-hidden rounded-xl border border-line bg-panel/70 backdrop-blur-sm">
            {HERO.stats.map((stat) => (
              <div key={stat.label} className="px-4 py-5 sm:px-6">
                <dt className="text-[10px] font-semibold uppercase tracking-[0.18em] text-faint sm:text-[11px]">
                  {stat.label}
                </dt>
                <dd className="mt-2 text-2xl font-bold tracking-tight text-ink sm:text-3xl">
                  {stat.value}
                </dd>
              </div>
            ))}
          </dl>
        </Reveal>
      </div>
    </section>
  );
}
