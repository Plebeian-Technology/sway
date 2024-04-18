import { MetaHTMLAttributes, StrictMode } from "react";
import { createInertiaApp } from '@inertiajs/react'
import { InertiaProgress } from "@inertiajs/progress";
import axios from "axios";
import { createRoot } from "react-dom/client";
import Layout from "../components/Layout";
import NoAuthLayoutWithPage from "../components/NoAuthLayout";
import { logDev } from "../sway_utils";
import { Provider } from "react-redux";
import { store } from "app/frontend/redux";

logDev("index.tsx")

// @ts-ignore
const pages = import.meta.glob("../pages/*.tsx", { eager: true });
logDev("pages", pages)

const NO_AUTH_LAYOUTS = ["home", "registration", "signuppasskey", "loginpasskey"];

document.addEventListener("DOMContentLoaded", () => {
    const csrfToken = (document.querySelector("meta[name=csrf-token]") as HTMLMetaElement | undefined)?.content;
    axios.defaults.headers.common["X-CSRF-Token"] = csrfToken;

    InertiaProgress.init();

    createInertiaApp({
        resolve: async (name: string) => {
            logDev("index.tsx - createInertiaApp - page name -", name);

            const LayoutComponent = NO_AUTH_LAYOUTS.includes(name.toLowerCase()) ? NoAuthLayoutWithPage : Layout;
            // const page = (await pages[`../pages/${name}.tsx`]()).default;
            // const page = (await pages[name.includes("../pages") ? name : `../pages/${name}.tsx`]()).default;
            // @ts-ignore
            const page = pages[`../pages/${name}.tsx`].default

            page.layout = page.layout || LayoutComponent;

            return page;
        },

        /**
         * React.StrictMode forces components to be rendered twice in development
         * https://stackoverflow.com/a/60619061/6410635
         */
        setup({ el, App, props }) {
            createRoot(el!).render(
                <StrictMode>
                    <Provider store={store}>
                    <App {...props} />
                    </Provider>
                </StrictMode>,
            );
        },
    }).catch(console.error);
});
