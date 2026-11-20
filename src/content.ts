/**
 * ---------------------------------------------------------------------------
 *  SITE CONTENT & CONFIGURATION
 * ---------------------------------------------------------------------------
 *  Every piece of editable copy, figure, URL and email address on the page
 *  lives in this file. Update text here; the components only read from it.
 *
 *  Copy rules: British English, no exclamation marks, no emojis, no hype.
 *  Speak to outcomes and access only.
 * ---------------------------------------------------------------------------
 */

/** Sign-in URL for the access-controlled Bid Pipeline (static page in public/pipeline/). */
export const DASHBOARD_URL = '/pipeline';

/** System admin console for the agency team (static page in public/admin/). */
export const ADMIN_URL = '/admin';

/** Public event submission form (no login), static page at public/pipeline/submit.html. */
export const SUBMIT_URL = '/pipeline/submit.html';

/** Address that receives access requests and event submissions. */
/**
 * Supabase project behind the access request queue. The anon key is public by
 * design; the request_access function validates and rate limits every call.
 */
export const SUPABASE_URL = 'https://upzkvszgoqhoefkiwoep.supabase.co';
export const SUPABASE_ANON_KEY =
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVwemt2c3pnb3Fob2Vma2l3b2VwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODIxMzg1MjQsImV4cCI6MjA5NzcxNDUyNH0.4RB-5FCWW7JXvGBKs0PlzkYcUeG5kTVxTVdoXUNp8ao';

export const CONTACT_EMAIL = 'nandie@farirainandipa.co.zw';

export const BRAND = {
  name: 'Africa MICE Dashboard',
  description:
    'Bid intelligence for African destinations, with the international and regional events open to bid in one place.',
  parentCompany: 'A product of Farirai Nandipa MICE Consultancy',
};

/** Primary navigation. The `href` values must match section ids below. */
export const NAV_LINKS = [
  { label: 'Platform', href: '#platform' },
  { label: "Who it's for", href: '#audience' },
  { label: 'How it works', href: '#how-it-works' },
  { label: 'Access', href: '#access' },
  { label: 'Submit an event', href: SUBMIT_URL },
];

export const CTA = {
  signIn: 'Sign in',
  requestAccess: 'Request access',
};

export const HERO = {
  overline: 'Bid intelligence for African destinations',
  headline: 'Know which MICE events African destinations can win.',
  subhead:
    'A curated, continuously updated pipeline of conferences, congresses, incentives and corporate events open to African hosts, with the context destinations need to decide, prioritise and bid.',
  /** Placeholder figures. Edit freely. */
  stats: [
    { value: '350+', label: 'Events tracked' },
    { value: '24', label: 'Sectors covered' },
    { value: '30+', label: 'Destinations served' },
  ],
};

/** Feature cards. `icon` is a key from the ICONS map in components/icons.ts. */
export const PLATFORM = {
  overline: 'Platform',
  heading: 'Everything a destination needs to decide where to bid.',
  intro: 'One clear view of the international and regional events open to Africa, and a direct route from opportunity to bid.',
  features: [
    {
      icon: 'pipeline',
      title: 'Live bid pipeline',
      body: 'See upcoming events open to bid, with timelines and key requirements at a glance.',
    },
    {
      icon: 'fit',
      title: 'Destination fit',
      body: 'Quickly judge which opportunities match your venues, capacity and sector strengths.',
    },
    {
      icon: 'shortlist',
      title: 'Prioritise and shortlist',
      body: 'Flag the opportunities worth pursuing and track them in one place.',
    },
    {
      icon: 'support',
      title: 'Bid support, when you want it',
      body: 'Move a shortlisted bid into a guided bid-development track with an experienced team.',
    },
  ],
} as const;

export const AUDIENCE = {
  overline: "Who it's for",
  heading: 'Built for the people who bring business events to Africa.',
  groups: [
    {
      icon: 'bureau',
      title: 'Convention bureaus & tourism boards',
      body: 'Grow your business-events calendar with a steady view of winnable bids.',
    },
    {
      icon: 'venue',
      title: 'PCOs, venues & DMCs',
      body: 'Spot congress and incentive business early and position for it.',
    },
    {
      icon: 'owner',
      title: 'Event owners & associations',
      body: 'Looking for an African host? Submit your event and reach destinations ready to bid.',
      cta: { label: 'Submit an event', href: SUBMIT_URL },
    },
  ],
} as const;

export const HOW_IT_WORKS = {
  overline: 'How it works',
  heading: 'From opportunity to bid in three steps.',
  steps: [
    { title: 'Access the dashboard', body: 'Your team signs in to a live view of events open to African hosts.' },
    { title: 'Shortlist what fits your destination', body: 'Focus on the opportunities you are best placed to win.' },
    { title: 'Pursue the bid, with or without our support', body: 'Run the bid yourself, or bring in our team to develop it with you.' },
  ],
};

export const CONTRIBUTE = {
  overline: 'Contribute',
  heading: 'Share an event or destination data with us.',
  intro: 'Two public forms feed the pipeline. Neither needs a login, and our team reviews every submission before it is used.',
  cards: [
    {
      icon: 'submit',
      title: 'Submit an event',
      body:
        'For corporates, associations, foundations and incentive houses whose conference is not tied to one country. Tell us about the event and when the host will be decided. There is no charge.',
      cta: { label: 'Submit an event', href: SUBMIT_URL },
    },
    {
      icon: 'partner',
      title: 'Destination partner data',
      body:
        'For convention bureaux and other in-country partners with first-hand data about a destination. Each data point needs a date and a source, and nothing goes live until it has been reviewed.',
      cta: { label: 'Submit destination data', href: '/pipeline/partner' },
    },
  ],
};

export const ACCESS = {
  overline: 'Access',
  heading: 'Request access',
  note:
    'Access is by subscription for destination and industry organisations. Tell us a little about your organisation and we will arrange a walkthrough.',
  points: [
    'Subscription access for your whole team',
    'A guided walkthrough before you commit',
    'Optional bid-development support',
  ],
  orgTypes: ['Convention bureau', 'Tourism board', 'PCO', 'Venue', 'DMC', 'Event owner', 'Other'],
  submitLabel: 'Request a walkthrough',
  emailSubject: 'Access request – Africa MICE Dashboard',
  successNote: 'Thank you. Your request is with our team and we will be in touch to arrange a walkthrough.',
  sendingLabel: 'Sending…',
  rateLimitNote: 'We have already received several requests from you. Please try again later or email us.',
  fallbackNote: 'We could not send the form, so your email app should now open with your request ready to send.',
};

/**
 * Footer links. The copyright and trade mark notice, the Terms of Access and
 * third-party notices links and the correction route come from legal.config.json
 * (see src/legal.ts), which the dashboard footers read too.
 */
export const FOOTER = {
  legalLinks: [
    { label: 'Privacy', href: '#' },
    { label: 'System admin', href: ADMIN_URL },
  ],
};
