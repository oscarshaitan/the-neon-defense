import {defineConfig} from 'vite';
import react from '@vitejs/plugin-react';

// Relative base so the build works from any served subpath
// (GitHub Pages serves it at /the-neon-defense/playground/build/web/).
export default defineConfig({
  base: './',
  plugins: [react()],
  build: {
    outDir: 'build/web',
    emptyOutDir: true,
  },
});
