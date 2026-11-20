import { BRAND, CTA, DASHBOARD_URL, FOOTER, NAV_LINKS } from '../content';
import Wordmark from './Wordmark';
import { LEGAL, fillLegal } from '../legal';

/** Footer with the wordmark, description, navigation, legal links and attribution. */
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
                <a href={DASHBOARD_URL} className="text-accent transition-colors hover:text-accent-strong">
                  {CTA.signIn}
                </a>
              </li>
            </ul>
          </nav>
        </div>

        <div className="mt-12 flex flex-col gap-4 border-t border-line pt-6 text-xs text-faint sm:flex-row sm:items-start sm:justify-between">
          <div className="max-w-2xl space-y-2 leading-relaxed">
            <p>{fillLegal(LEGAL.footerNotice)}</p>
            <p className="text-faint/80">{BRAND.parentCompany}</p>
            <p>
              {LEGAL.rightsPrompt}{' '}
              <a href={LEGAL.links.rights.href} className="text-muted underline-offset-2 transition-colors hover:text-ink hover:underline">
                {LEGAL.rightsLinkText}
              </a>
            </p>
          </div>
          <ul className="flex flex-wrap gap-x-6 gap-y-2">
            {[LEGAL.links.terms, LEGAL.links.notices, ...FOOTER.legalLinks].map((link) => (
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
