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

/** Address that receives access requests and event submissions. */
export const CONTACT_EMAIL = 'nandie@farirainandipa.co.zw';

export const BRAND = {
  name: 'Africa MICE Dashboard',
  description:
    'Bid intelligence for African destinations, with the international events open to bid in one place.',
  parentCompany: 'A product of Farirai Nandipa MICE Consultancy',
  copyrightYear: 2026,
};

/** Primary navigation. The `href` values must match section ids below. */
export const NAV_LINKS = [
  { label: 'Platform', href: '#platform' },
  { label: "Who it's for", href: '#audience' },
  { label: 'How it works', href: '#how-it-works' },
  { label: 'Access', href: '#access' },
];

export const CTA = {
  signIn: 'Sign in',
  requestAccess: 'Request access',
};

export const HERO = {
  overline: 'Bid intelligence for African destinations',
  headline: 'Know which international events Africa can win, before the bid closes.',
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
  intro: 'One clear view of the international business open to Africa, and a direct route from opportunity to bid.',
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
      cta: {
        label: 'Submit an event',
        subject: 'Event submission – Africa MICE Dashboard',
        body:
          'Event name:\nOrganisation:\nEvent type (conference / congress / incentive / corporate):\nPreferred dates or year:\nExpected attendance:\nBid deadline (if known):\nContact name and role:\n',
      },
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

export const TRUST = {
  overline: 'Credibility',
  heading: 'Built by business-events professionals working across Africa.',
  /** Placeholder logos. Replace with real partner/client logos (one entry per logo). */
  logos: ['Logo', 'Logo', 'Logo', 'Logo', 'Logo', 'Logo'],
  testimonial: {
    quote:
      'Placeholder testimonial. A short line from a convention bureau or tourism board on how the dashboard changed the way they choose which events to pursue.',
    name: 'Full Name',
    role: 'Title, Organisation, Country',
  },
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
  successNote: 'Your email app should now open with your request ready to send.',
};

export const FOOTER = {
  legalLinks: [
    { label: 'Privacy', href: '#' },
    { label: 'Terms', href: '#' },
  ],
};
