import { InertiaProgress } from "@inertiajs/progress";
import { createInertiaApp } from "@inertiajs/react";
import LayoutWithPage from "app/frontend/components/Layout";
import NoAuthLayout from "app/frontend/components/NoAuthLayout";
import { store } from "app/frontend/redux";
import axios from "axios";
import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { Provider } from "react-redux";
import { logDev } from "../sway_utils";
import { Toaster } from "react-hot-toast";

// Load react-select
// @ts-ignore
import Select from "react-select"; // eslint-disable-line

logDev("index.tsx");

// @ts-ignore

const NO_AUTH_LAYOUTS = ["home", "registration"];

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
                    <Provider store={store(props.initialPage.props)}>
                        <App {...props} />
                        <Toaster />
                    </Provider>
                </StrictMode>,
            );
        },
    }).catch(console.error);
});
