import { SentryUtil } from "app/frontend/sway_utils/sentry";
SentryUtil.init(); // only fulfilled in prod

import { InertiaProgress } from "@inertiajs/progress";
import { createInertiaApp } from "@inertiajs/react";
import { ErrorBoundary } from "@sentry/react";
import LayoutWithPage from "app/frontend/components/Layout";
import NoAuthLayout from "app/frontend/components/NoAuthLayout";
import RenderErrorHandler from "app/frontend/components/error_handling/RenderErrorHandler";
import { onRenderError } from "app/frontend/components/error_handling/utils";
import { store } from "app/frontend/redux";
import axios from "axios";
import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { Toaster } from "react-hot-toast";
import { Provider } from "react-redux";
import { logDev } from "../sway_utils";

// const RECAPTCHA__SCRIPT_PROPS = {
//     async: true, // optional, default to false,
//     defer: false, // optional, default to false
//     appendTo: "head", // optional, default to "head", can be "head" or "body",
//     nonce: undefined, // optional, default undefined
// } as const;

const NO_AUTH_LAYOUTS = ["home", "registration"];

const pages = import.meta.glob("../pages/*.tsx", { eager: true }) as Record<string, any>;

document.addEventListener("DOMContentLoaded", () => {
    // https://stackoverflow.com/a/56144709/6410635
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
            logDev("application.tsx - render App", { el, App, props });
            createRoot(el!).render(
                <ErrorBoundary onError={onRenderError} fallback={<RenderErrorHandler />}>
                    {/* <GoogleReCaptchaProvider
                        reCaptchaKey={import.meta.env.VITE_GOOGLE_RECAPTCHA_SITE_KEY}
                        language="en"
                        useEnterprise={true}
                        scriptProps={RECAPTCHA__SCRIPT_PROPS}
                    > */}
                    <StrictMode>
                        <Provider store={store(props.initialPage.props)}>
                            <App {...props} />
                            <Toaster />
                        </Provider>
                    </StrictMode>
                    {/* </GoogleReCaptchaProvider> */}
                </ErrorBoundary>,
            );
        },
    }).catch(console.error);
});
