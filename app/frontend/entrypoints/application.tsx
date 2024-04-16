import { StrictMode } from 'react'
import { createInertiaApp } from '@inertiajs/inertia-react'
import { InertiaProgress } from '@inertiajs/progress';
import axios from 'axios';
import Layout from '../components/Layout';
import { createRoot } from 'react-dom/client';

// @ts-ignore
const pages = import.meta.glob('../pages/*.tsx')

document.addEventListener('DOMContentLoaded', () => {
  const csrfToken = document.querySelector('meta[name=csrf-token]')?.textContent;
  axios.defaults.headers.common['X-CSRF-Token'] = csrfToken;

  InertiaProgress.init();

  createInertiaApp({
    resolve: async name => {
      const page = (await pages[`../pages/${name}.tsx`]()).default;
      page.layout = page.layout || Layout

      return page
    },

    /**
     * React.StrictMode forces components to be rendered twice in development
     * https://stackoverflow.com/a/60619061/6410635
    */
    setup({ el, App, props }) {
      createRoot(el!).render(
            <StrictMode>
              <App {...props} />
            </StrictMode>
      );
    },
  }).catch(console.error)
});