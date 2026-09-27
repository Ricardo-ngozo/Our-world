import { defineConfig } from 'vite';

// Set VITE_APP_VARIANT=second on the second Render service to give its
// installed PWA a distinct icon. The primary deployment keeps its existing icon.
export default defineConfig(() => {
  const secondApp = process.env.VITE_APP_VARIANT === 'second';

  return {
    plugins: [
      {
        name: 'couple-app-branding',
        transformIndexHtml(html) {
          if (!secondApp) return html;
          return html
            .replaceAll('/icon-192.svg', '/icon-second.svg')
            .replaceAll('/icon.svg', '/icon-second.svg')
            .replace('/manifest.webmanifest', '/manifest-second.webmanifest')
            .replace('content="Our World"', 'content="Our World 2"');
        },
      },
    ],
  };
});
