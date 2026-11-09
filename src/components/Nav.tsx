import { useEffect, useState } from 'react';
import { Menu, X } from 'lucide-react';
import { BRAND, CTA, DASHBOARD_URL, NAV_LINKS } from '../content';
import Wordmark from './Wordmark';
import { ButtonLink } from './Button';

/** Sticky top navigation with a collapsible menu on small screens. */
export default function Nav() {
  const [scrolled, setScrolled] = useState(false);
  const [open, setOpen] = useState(false);

  // Add a solid backdrop once the page has scrolled away from the top.
  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 8);
    onScroll();
    window.addEventListener('scroll', onScroll, { passive: true });
    return () => window.removeEventListener('scroll', onScroll);
  }, []);

  const close = () => setOpen(false);

  return (
    <header
      className={`sticky top-0 z-50 border-b transition-colors duration-300 ${
        scrolled || open ? 'border-line bg-navy/85 backdrop-blur-md' : 'border-transparent bg-transparent'
      }`}
    >
      <nav aria-label="Primary" className="mx-auto flex h-16 max-w-6xl items-center justify-between gap-4 px-5 sm:px-8">
        <a href="#top" aria-label={`${BRAND.name}, back to top`} onClick={close}>
          <Wordmark />
        </a>

        <ul className="hidden items-center gap-8 lg:flex">
          {NAV_LINKS.map((link) => (
            <li key={link.href}>
              <a href={link.href} className="text-sm font-medium text-muted transition-colors hover:text-ink">
                {link.label}
              </a>
            </li>
          ))}
        </ul>

        <div className="hidden items-center gap-3 lg:flex">
          <ButtonLink variant="ghost" href={DASHBOARD_URL}>
            {CTA.signIn}
          </ButtonLink>
          <ButtonLink href="#access">{CTA.requestAccess}</ButtonLink>
        </div>

        <button
          type="button"
          className="inline-flex h-10 w-10 shrink-0 items-center justify-center rounded-lg border border-line text-ink lg:hidden"
          aria-expanded={open}
          aria-controls="mobile-menu"
          aria-label={open ? 'Close menu' : 'Open menu'}
          onClick={() => setOpen((v) => !v)}
        >
          {open ? <X size={18} /> : <Menu size={18} />}
        </button>
      </nav>

      {/* Mobile menu */}
      {open && (
        <div id="mobile-menu" className="border-t border-line px-5 pb-6 pt-2 lg:hidden">
          <ul className="flex flex-col">
            {NAV_LINKS.map((link) => (
              <li key={link.href}>
                <a href={link.href} onClick={close} className="block border-b border-line py-3.5 text-base font-medium text-ink">
                  {link.label}
                </a>
              </li>
            ))}
          </ul>
          <div className="mt-5 grid grid-cols-2 gap-3">
            <ButtonLink variant="ghost" href={DASHBOARD_URL}>
              {CTA.signIn}
            </ButtonLink>
            <ButtonLink href="#access" onClick={close}>
              {CTA.requestAccess}
            </ButtonLink>
          </div>
        </div>
      )}
    </header>
  );
}
