import { defineConfig, type Plugin } from 'vite';
import react from '@vitejs/plugin-react';
import tailwindcss from '@tailwindcss/vite';
import legal from './legal.config.json';

/**
 * legal.config.json is the one place for the owner entity and footer wording.
 * The landing page imports it directly; this plugin also serves it to the static
 * pages (pipeline, admin, legal) as /legal/config.js, in dev and in the build.
 */
function legalConfig(): Plugin {
  const { _comment, ...cfg } = legal;
  void _comment;
  const js = () => `window.LEGAL = ${JSON.stringify(cfg)};\n`;
  return {
    name: 'legal-config',
    configureServer(server) {
      server.middlewares.use('/legal/config.js', (_req, res) => {
        res.setHeader('Content-Type', 'text/javascript; charset=utf-8');
        res.end(js());
      });
    },
    generateBundle() {
      this.emitFile({ type: 'asset', fileName: 'legal/config.js', source: js() });
    },
  };
}

export default defineConfig({
  plugins: [react(), tailwindcss(), legalConfig()],
});
