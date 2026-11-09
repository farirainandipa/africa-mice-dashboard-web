import { useState, type ChangeEvent, type FormEvent, type ReactElement } from 'react';
import { Check, CheckCircle2 } from 'lucide-react';
import { ACCESS, CONTACT_EMAIL } from '../content';
import { buildMailto } from '../lib/mailto';
import { Button } from './Button';
import Reveal from './Reveal';

type FieldName = 'name' | 'organisation' | 'orgType' | 'country' | 'email' | 'message';
type FormValues = Record<FieldName, string>;
type FormErrors = Partial<Record<FieldName, string>>;

const EMPTY: FormValues = { name: '', organisation: '', orgType: '', country: '', email: '', message: '' };
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

/** Client-side validation of required fields. Returns an error message per invalid field. */
function validate(v: FormValues): FormErrors {
  const errors: FormErrors = {};
  if (!v.name.trim()) errors.name = 'Please enter your full name.';
  if (!v.organisation.trim()) errors.organisation = 'Please enter your organisation.';
  if (!v.orgType) errors.orgType = 'Please choose an organisation type.';
  if (!v.country.trim()) errors.country = 'Please enter your country.';
  if (!v.email.trim()) errors.email = 'Please enter your work email.';
  else if (!EMAIL_PATTERN.test(v.email.trim())) errors.email = 'Please enter a valid email address.';
  return errors;
}

/** Formats the form values as a plain-text email body. */
function buildBody(v: FormValues): string {
  return [
    `Full name: ${v.name.trim()}`,
    `Organisation: ${v.organisation.trim()}`,
    `Organisation type: ${v.orgType}`,
    `Country: ${v.country.trim()}`,
    `Work email: ${v.email.trim()}`,
    '',
    'Message:',
    v.message.trim() || '(none)',
  ].join('\n');
}

const inputClass =
  'mt-2 block w-full rounded-lg border bg-navy px-3.5 py-2.5 text-[15px] text-ink placeholder:text-faint transition-colors focus:outline-none focus:ring-2 focus:ring-accent/40';

/** Access section: subscription note and the request form (opens a prefilled mailto). */
export default function AccessForm() {
  const [values, setValues] = useState<FormValues>(EMPTY);
  const [errors, setErrors] = useState<FormErrors>({});
  const [sent, setSent] = useState(false);

  const onChange = (e: ChangeEvent<HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement>) => {
    const name = e.target.name as FieldName;
    setValues((prev) => ({ ...prev, [name]: e.target.value }));
    // Clear a field's error as soon as the user edits it.
    if (errors[name]) setErrors((prev) => ({ ...prev, [name]: undefined }));
  };

  const onSubmit = (e: FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    const found = validate(values);
    setErrors(found);
    const firstInvalid = Object.keys(found)[0];
    if (firstInvalid) {
      document.getElementById(`field-${firstInvalid}`)?.focus();
      return;
    }
    window.location.href = buildMailto(CONTACT_EMAIL, ACCESS.emailSubject, buildBody(values));
    setSent(true);
  };

  /** Shared label + control + error wiring for each field. */
  const field = (name: FieldName, label: string, control: (props: Record<string, unknown>) => ReactElement, optional = false) => {
    const error = errors[name];
    const id = `field-${name}`;
    return (
      <div>
        <label htmlFor={id} className="text-sm font-medium text-ink">
          {label}
          {optional ? <span className="ml-1.5 text-faint">(optional)</span> : <span className="ml-0.5 text-accent" aria-hidden="true">*</span>}
        </label>
        {control({
          id,
          name,
          value: values[name],
          onChange,
          required: !optional,
          'aria-invalid': error ? true : undefined,
          'aria-describedby': error ? `${id}-error` : undefined,
          className: `${inputClass} ${error ? 'border-red-400/70' : 'border-line hover:border-white/20'}`,
        })}
        {error && (
          <p id={`${id}-error`} className="mt-1.5 text-sm text-red-300">
            {error}
          </p>
        )}
      </div>
    );
  };

  return (
    <section id="access" aria-labelledby="access-heading" className="relative border-t border-line py-20 sm:py-28">
      <div aria-hidden="true" className="pointer-events-none absolute inset-x-0 top-0 -z-10 h-96 bg-gradient-to-b from-accent/[0.06] to-transparent" />
      <div className="mx-auto grid max-w-6xl gap-12 px-5 sm:px-8 lg:grid-cols-[1fr_1.25fr] lg:gap-16">
        <Reveal>
          <p className="text-xs font-semibold uppercase tracking-[0.22em] text-accent">{ACCESS.overline}</p>
          <h2 id="access-heading" className="mt-4 text-3xl font-bold tracking-tight text-ink sm:text-4xl">
            {ACCESS.heading}
          </h2>
          <p className="mt-5 max-w-md text-base leading-relaxed text-muted sm:text-lg">{ACCESS.note}</p>
          <ul className="mt-8 space-y-3">
            {ACCESS.points.map((point) => (
              <li key={point} className="flex items-start gap-3 text-[15px] text-ink">
                <Check size={18} className="mt-0.5 shrink-0 text-accent" aria-hidden="true" />
                {point}
              </li>
            ))}
          </ul>
        </Reveal>

        <Reveal delay={120}>
          <form noValidate onSubmit={onSubmit} className="rounded-xl border border-line bg-panel p-6 sm:p-8">
            <div className="grid gap-5 sm:grid-cols-2">
              {field('name', 'Full name', (p) => <input type="text" autoComplete="name" {...p} />)}
              {field('organisation', 'Organisation', (p) => <input type="text" autoComplete="organization" {...p} />)}
              {field('orgType', 'Organisation type', (p) => (
                <select {...p}>
                  <option value="" disabled>
                    Select…
                  </option>
                  {ACCESS.orgTypes.map((t) => (
                    <option key={t} value={t}>
                      {t}
                    </option>
                  ))}
                </select>
              ))}
              {field('country', 'Country', (p) => <input type="text" autoComplete="country-name" {...p} />)}
              <div className="sm:col-span-2">
                {field('email', 'Work email', (p) => <input type="email" autoComplete="email" inputMode="email" {...p} />)}
              </div>
              <div className="sm:col-span-2">
                {field('message', 'Message', (p) => <textarea rows={4} {...p} />, true)}
              </div>
            </div>

            <Button type="submit" className="mt-7 w-full py-3 text-[15px] sm:w-auto sm:px-7">
              {ACCESS.submitLabel}
            </Button>

            <p className="mt-4 text-xs leading-relaxed text-faint" aria-live="polite">
              {sent && (
                <span className="inline-flex items-center gap-1.5 text-accent">
                  <CheckCircle2 size={14} aria-hidden="true" />
                  {ACCESS.successNote}
                </span>
              )}
            </p>
          </form>
        </Reveal>
      </div>
    </section>
  );
}
