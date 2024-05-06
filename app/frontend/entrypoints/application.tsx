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
import { GoogleReCaptchaProvider } from "react-google-recaptcha-v3";

// Load react-select
// @ts-ignore
import Select from "react-select"; // eslint-disable-line

const RECAPTCHA__SCRIPT_PROPS = {
    async: true, // optional, default to false,
    defer: false, // optional, default to false
    appendTo: "head", // optional, default to "head", can be "head" or "body",
    nonce: undefined, // optional, default undefined
} as const;

const NO_AUTH_LAYOUTS = ["home", "registration"];

const pages = import.meta.glob("../pages/*.tsx", { eager: true }) as Record<string, any>;
logDev("pages", pages);

document.addEventListener("DOMContentLoaded", () => {
    const csrfToken = (document.querySelector("meta[name=csrf-token]") as HTMLMetaElement | undefined)?.content;
    axios.defaults.headers.common["X-CSRF-Token"] = csrfToken;

    InertiaProgress.init();

    createInertiaApp({
        resolve: async (pageName: string) => {
            logDev("index.tsx - createInertiaApp - page pageName -", pageName);

            const LayoutComponent = NO_AUTH_LAYOUTS.includes(pageName.toLowerCase()) ? NoAuthLayout : LayoutWithPage;

            let page = pages[`../pages/${pageName}.tsx`];
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
            createRoot(el!).render(
                <GoogleReCaptchaProvider
                    reCaptchaKey={import.meta.env.VITE_GOOGLE_RECAPTCHA_SITE_KEY}
                    language="en"
                    useEnterprise={true}
                    scriptProps={RECAPTCHA__SCRIPT_PROPS}
                    // container={{
                    //     element: "app",
                    //     parameters: {
                    //         badge: undefined,
                    //         theme: "light",
                    //     },
                    // }}
                >
                    <StrictMode>
                        <Provider store={store(props.initialPage.props)}>
                            <App {...props} />
                            <Toaster />
                        </Provider>
                    </StrictMode>
                </GoogleReCaptchaProvider>,
            );
        },
    }).catch(console.error);
});
