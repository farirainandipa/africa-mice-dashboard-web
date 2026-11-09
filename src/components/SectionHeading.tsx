import Reveal from './Reveal';

interface SectionHeadingProps {
  overline: string;
  heading: string;
  intro?: string;
  /** Id for the heading, so the section can reference it via aria-labelledby. */
  id?: string;
  align?: 'left' | 'center';
}

/** Shared overline + headline + optional intro used at the top of each section. */
export default function SectionHeading({ overline, heading, intro, id, align = 'left' }: SectionHeadingProps) {
  const centred = align === 'center';
  return (
    <Reveal className={`max-w-2xl ${centred ? 'mx-auto text-center' : ''}`}>
      <p className="text-xs font-semibold uppercase tracking-[0.22em] text-accent">{overline}</p>
      <h2 id={id} className="mt-4 text-3xl font-bold leading-tight tracking-tight text-ink sm:text-4xl">
        {heading}
      </h2>
      {intro && <p className="mt-4 text-base leading-relaxed text-muted sm:text-lg">{intro}</p>}
    </Reveal>
  );
}
