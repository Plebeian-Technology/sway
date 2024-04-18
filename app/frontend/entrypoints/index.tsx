import { StrictMode } from "react";
import { createInertiaApp } from '@inertiajs/inertia-react'
// import { createInertiaApp } from '@inertiajs/react'
import { InertiaProgress } from "@inertiajs/progress";
import axios from "axios";
import { createRoot } from "react-dom/client";
import Layout from "../components/Layout";
import NoAuthLayoutWithPage from "../components/NoAuthLayout";
import { logDev } from "../sway_utils";

// @ts-ignore
const pages = import.meta.glob("../pages/*.tsx", { eager: true });

const NO_AUTH_LAYOUTS = ["home", "login", "sign_up", "registration", "passwordreset"];

document.addEventListener("DOMContentLoaded", () => {
    const csrfToken = document.querySelector("meta[name=csrf-token]")?.textContent;
    axios.defaults.headers.common["X-CSRF-Token"] = csrfToken;

    InertiaProgress.init();

    createInertiaApp({
        resolve: async (name) => {
            logDev("index.tsx - createInertiaApp - page name -", name);

            const LayoutComponent = NO_AUTH_LAYOUTS.includes(name.toLowerCase()) ? NoAuthLayoutWithPage : Layout;
            const page = (await pages[`../pages/${name}.tsx`]()).default;

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
                    <App {...props} />
                </StrictMode>,
            );
        },
    }).catch(console.error);
});
