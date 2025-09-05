module.exports = {
  title: 'My Docs',
  url: 'http://localhost',
  baseUrl: '/',
  onBrokenLinks: 'throw',
  onBrokenMarkdownLinks: 'warn',
  i18n: { defaultLocale: 'en', locales: ['en'] },

  presets: [
    [
      'classic',
      {
        docs: {
          routeBasePath: '/',                 // serve docs at root
          sidebarPath: require.resolve('./sidebars.js'),
          editUrl: undefined,                 // hide "Edit this page"
          showLastUpdateAuthor: false,
          showLastUpdateTime: false,
        },
        blog: false,                          // drop the blog
        theme: { customCss: require.resolve('./src/css/custom.css') },
      },
    ],
  ],

  // Keep this section tiny
  themeConfig: {
    navbar: {
      title: 'My Docs',
      items: [{ type: 'doc', docId: 'intro', label: 'Docs', position: 'left' }],
    },
    // Remove footer entirely if you don’t want it:
    // footer: undefined,
  },
};
