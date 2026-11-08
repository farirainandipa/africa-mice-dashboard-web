# Africa MICE Dashboard — landing site

Single-page marketing site for Africa MICE Dashboard. Vite + React + TypeScript, Tailwind CSS v4, lucide-react.

```bash
npm install
npm run dev      # local dev server
npm run build    # production build into dist/
```

## Editing content

All copy, stats, URLs and the contact email live in **`src/content.ts`**. Components only read from it.

- `DASHBOARD_URL` — external "Sign in" link.
- `CONTACT_EMAIL` — receives access requests (form) and event submissions.
- `HERO.stats` — placeholder figures for the stat chips.
- `TRUST.logos` / `TRUST.testimonial` — placeholder logos and testimonial.
- `FOOTER.legalLinks` — Privacy and Terms URLs.

Also update the OpenGraph URLs and image in `index.html`, and replace `public/favicon.svg` if needed.

## Structure

```
src/
  content.ts            editable copy and configuration
  lib/mailto.ts         mailto: URL builder
  components/
    Nav, Hero, Platform, Audience, HowItWorks, Trust, AccessForm, Footer
    AfricaDots          decorative dotted continent for the hero
    Reveal              fade/slide-in on scroll (respects reduced motion)
    Button, Wordmark, SectionHeading, icons
```

There is no backend: the access form validates required fields, then opens a prefilled email to `CONTACT_EMAIL`.
