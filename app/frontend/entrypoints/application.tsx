import { SentryUtil } from "app/frontend/sway_utils/sentry";
SentryUtil.init().catch(console.error); // only fulfilled in prod

import { InertiaProgress } from "@inertiajs/progress";
import { createInertiaApp } from "@inertiajs/react";
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

import "app/frontend/styles";

const NO_AUTH_LAYOUTS = ["home", "registration"];

const pages = import.meta.glob("../pages/*.tsx", { eager: true }) as Record<string, any>;

document.addEventListener("DOMContentLoaded", () => {
    const Sentry = import("@sentry/react");

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
            Sentry.then(({ ErrorBoundary }) => {
                createRoot(el!).render(
                    <ErrorBoundary onError={onRenderError} fallback={<RenderErrorHandler />}>
                        <StrictMode>
                            <Provider store={store(props.initialPage.props)}>
                                <App {...props} />
                                <Toaster />
                            </Provider>
                        </StrictMode>
                    </ErrorBoundary>,
                );
            });
        },
    }).catch(console.error);
});
