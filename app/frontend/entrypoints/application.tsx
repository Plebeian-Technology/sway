import { InertiaProgress } from "@inertiajs/progress";
import { createInertiaApp } from "@inertiajs/react";
import { store } from "app/frontend/redux";
import axios from "axios";
import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { Provider } from "react-redux";
import { logDev } from "../sway_utils";

logDev("index.tsx");

// @ts-ignore

const NO_AUTH_LAYOUTS = ["home", "registration", "passkey"];

const pages = import.meta.glob("../pages/*.tsx", { eager: true }) as Record<string, any>;
logDev("pages", pages);

document.addEventListener("DOMContentLoaded", () => {
    const csrfToken = (document.querySelector("meta[name=csrf-token]") as HTMLMetaElement | undefined)?.content;
    axios.defaults.headers.common["X-CSRF-Token"] = csrfToken;
    
    InertiaProgress.init();
    
    createInertiaApp({
        resolve: async (name: string) => {

            logDev("index.tsx - createInertiaApp - page name -", name);

            // const LayoutComponent = NO_AUTH_LAYOUTS.includes(name.toLowerCase()) ? NoAuthLayout : Layout;
            
            let page = pages[`../pages/${name}.tsx`]
            page = page && "default" in page ? page.default : page;

            if (page) {
                // page.layout = page.layout || LayoutComponent;
    
                logDev("index.tsx - createInertiaApp - return page -", name);
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
