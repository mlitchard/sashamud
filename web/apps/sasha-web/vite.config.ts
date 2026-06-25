import { defineConfig } from 'vite';

export default defineConfig({
  root: 'src',
  build: {
    outDir: '../dist',
    emptyOutDir: true,
  },
  server: {
    proxy: {
      '/ws': {
        target: 'http://localhost:8081',
        ws: true,
      },
      '/api': {
        target: 'http://localhost:8081',
      },
    },
  },
});
