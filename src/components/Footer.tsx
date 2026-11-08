import { BRAND, CTA, DASHBOARD_URL, FOOTER, NAV_LINKS } from '../content';
import Wordmark from './Wordmark';

/** Footer: wordmark, description, navigation, legal links and attribution. */
export default function Footer() {
  return (
    <footer className="border-t border-line">
      <div className="mx-auto max-w-6xl px-5 py-14 sm:px-8">
        <div className="flex flex-col gap-10 md:flex-row md:items-start md:justify-between">
          <div className="max-w-sm">
            <Wordmark />
            <p className="mt-4 text-sm leading-relaxed text-muted">{BRAND.description}</p>
          </div>

          <nav aria-label="Footer">
            <ul className="grid grid-cols-2 gap-x-12 gap-y-3 text-sm sm:flex sm:flex-wrap sm:gap-x-8">
              {NAV_LINKS.map((link) => (
                <li key={link.href}>
                  <a href={link.href} className="text-muted transition-colors hover:text-ink">
                    {link.label}
                  </a>
                </li>
              ))}
              <li>
                <a href={DASHBOARD_URL} target="_blank" rel="noopener noreferrer" className="text-accent transition-colors hover:text-accent-strong">
                  {CTA.signIn}
                </a>
              </li>
            </ul>
          </nav>
        </div>

        <div className="mt-12 flex flex-col gap-4 border-t border-line pt-6 text-xs text-faint sm:flex-row sm:items-center sm:justify-between">
          <div className="space-y-1">
            <p>
              © {BRAND.copyrightYear} {BRAND.name}
            </p>
            <p className="text-faint/80">{BRAND.parentCompany}</p>
          </div>
          <ul className="flex gap-6">
            {FOOTER.legalLinks.map((link) => (
              <li key={link.label}>
                <a href={link.href} className="transition-colors hover:text-ink">
                  {link.label}
                </a>
              </li>
            ))}
          </ul>
        </div>
      </div>
    </footer>
  );
}
