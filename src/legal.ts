/**
 * Owner entity, footer notice and legal links, read from legal.config.json at the
 * repository root. The static pipeline, admin and legal pages read the same file
 * as /legal/config.js, so changing it changes every footer.
 */
import config from '../legal.config.json';

export const LEGAL = config;

/** Replaces {owner}, {product} and {year} with the configured values. */
export const fillLegal = (text: string) =>
  text
    .replaceAll('{owner}', config.owner)
    .replaceAll('{product}', config.product)
    .replaceAll('{year}', String(config.copyrightYear));
