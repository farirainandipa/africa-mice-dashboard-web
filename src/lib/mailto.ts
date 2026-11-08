/** Builds a `mailto:` URL with an encoded subject and body. */
export function buildMailto(to: string, subject: string, body = ''): string {
  const params = [`subject=${encodeURIComponent(subject)}`];
  if (body) params.push(`body=${encodeURIComponent(body)}`);
  return `mailto:${to}?${params.join('&')}`;
}
