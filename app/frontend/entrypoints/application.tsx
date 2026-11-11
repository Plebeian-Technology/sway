// @lat: [[use-theme-server-driven-no-effect#Why fromServerId checks against isValidThemeId instead of its own list]]

import { SentryUtil } from "app/frontend/sway_utils/sentry";
import { registerPWA } from "app/frontend/service-worker/registerSW";
import { reportWhyThePageReloaded } from "app/frontend/dev/reportWhyThePageReloaded";
SentryUtil.init().catch(console.error);

// @lat: [[dev-reload-reason-diagnostic#Development only]]
reportWhyThePageReloaded();

import "app/frontend/polyfills/scroll_restoration_on_back";
// @lat: [[query-parameter-navigation-carry#Centralized interception mechanism]]
import "app/frontend/sway_utils/queryParamNavigationCarry";
import "app/frontend/navigation/coalesceReloads";

import { createInertiaApp } from "@inertiajs/react";
import * as ActiveStorage from "@rails/activestorage";
import AppErrorFallback from "app/frontend/components/error_handling/AppErrorFallback";
import { onRenderError } from "app/frontend/components/error_handling/utils";
import { createRoot } from "react-dom/client";
import type { ComponentType } from "react";
import { logDev } from "app/frontend/sway_utils";
import { registerFlashToasts } from "app/frontend/sway_utils/flashToasts";

import App from "app/frontend/App";
import AuthLayout from "app/frontend/components/layouts/AuthLayout";
import NoAuthLayout from "app/frontend/components/layouts/NoAuthLayout";
import { resolvePageLoader } from "app/frontend/pageResolver";

// @lat: [[application-entrypoint-bootstrap-notes#Why "passkey" and "registration" were removed from NO_AUTH_LAYOUTS]]
const NO_AUTH_LAYOUTS = ["home", "swayregistration"];

const pages = import.meta.glob(["../pages/**/*.tsx", "!../pages/**/__tests__/**", "!../pages/**/*.test.tsx"]) as Record<
    string,
    any
>;

type InertiaPageComponent = ComponentType<any> & {
    layout?: any;
};

// @lat: [[lat#Sway]]
document.addEventListener("DOMContentLoaded", () => {
    ActiveStorage.start();
    registerFlashToasts();
    const isEmbedPage = window.location.pathname.startsWith("/embed/");

    // @lat: [[application-entrypoint-bootstrap-notes#Why the entrypoint bails out when the document carries no Inertia payload]]
    if (!document.querySelector("[data-page]")) {
        document.getElementById("application-loading")?.remove();
        if (!isEmbedPage) {
            registerPWA();
        }
        return;
    }

    const Sentry = import("@sentry/react");

    createInertiaApp({
        progress: {
            delay: 250,
            color: "#29d",
            includeCSS: true,
            showSpinner: false,
        },

        resolve: async (_pageName: string) => {
            const { loader, pageName } = resolvePageLoader(_pageName, pages);

            logDev("index.tsx - createInertiaApp - page pageName -", pageName);

            const LayoutComponent =
                isEmbedPage || NO_AUTH_LAYOUTS.includes(pageName.toLowerCase()) ? NoAuthLayout : AuthLayout;

            return Promise.resolve(loader()).then((_page) => {
                const page = ((_page as { default?: InertiaPageComponent }).default ??
                    (_page as InertiaPageComponent | undefined)) as InertiaPageComponent | undefined;

                if (!page) {
                    throw new Error(`Resolved page "${pageName}" did not export a component.`);
                }

                logDev("index.tsx - createInertiaApp - page found -", page.name);
                page.layout = page.layout || LayoutComponent;

                logDev("index.tsx - createInertiaApp - return page -", pageName);
                return page;
            });
        },

        setup({ el, App: InertiaApp, props }) {
            logDev("application.tsx - render App", { el, InertiaApp, props: props.initialPage.props });
            Sentry.then(({ ErrorBoundary: SentryErrorBoundary }) => {
                createRoot(el!).render(
                    <SentryErrorBoundary onError={onRenderError} fallback={<AppErrorFallback />}>
                        <App>
                            <InertiaApp {...props} />
                        </App>
                    </SentryErrorBoundary>,
                );
            }).catch(console.error);
        },
    }).catch(console.error);

    if (!isEmbedPage) {
        registerPWA();
    }
});
