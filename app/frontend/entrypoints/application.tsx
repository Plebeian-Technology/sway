import { InertiaProgress } from "@inertiajs/progress";
import { createInertiaApp } from "@inertiajs/react";
import { store } from "app/frontend/redux";
import axios from "axios";
import { StrictMode, createElement } from "react";
import { createRoot } from "react-dom/client";
import { Provider } from "react-redux";
import { logDev } from "../sway_utils";
import LayoutWithPage from "app/frontend/components/Layout";
import NoAuthLayout from "app/frontend/components/NoAuthLayout";

logDev("index.tsx");

// @ts-ignore

const NO_AUTH_LAYOUTS = ["home", "registration"];
const BUBBLE_LAYOUTS = ["home"];

const pages = import.meta.glob("../pages/*.tsx", { eager: true }) as Record<string, any>;
logDev("pages", pages);

document.addEventListener("DOMContentLoaded", () => {
    const csrfToken = (document.querySelector("meta[name=csrf-token]") as HTMLMetaElement | undefined)?.content;
    axios.defaults.headers.common["X-CSRF-Token"] = csrfToken;
    // axios.defaults.headers.common["Content-Type"] = "application/json";
    
    InertiaProgress.init();
    
    createInertiaApp({
        resolve: async (pageName: string) => {

            logDev("index.tsx - createInertiaApp - page pageName -", pageName);

            const LayoutComponent = NO_AUTH_LAYOUTS.includes(pageName.toLowerCase()) ? NoAuthLayout : LayoutWithPage;
            
            let page = pages[`../pages/${pageName}.tsx`]
            page = page && "default" in page ? page.default : page;

            if (page) {
                page.layout = page.layout || LayoutComponent;
    
                logDev("index.tsx - createInertiaApp - return page -", pageName);
                return page;
            }

        },

        /**
         * React.StrictMode forces components to be rendered twice in development
         * https://stackoverflow.com/a/60619061/6410635
         */
        setup({ el, App, props }) {
            logDev("APPLICATION", { el, App, props })
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
