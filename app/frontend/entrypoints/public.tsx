// @lat: [[public-disclosure-pages#Public disclosure pages#Why the component tests are the only cover for the text]]

// @lat: [[application-entrypoint-bootstrap-notes#Why the entrypoint bails out when the document carries no Inertia payload]]

import { SentryUtil } from "app/frontend/sway_utils/sentry";
SentryUtil.init().catch(console.error); // only fulfilled in prod

import { createInertiaApp } from "@inertiajs/react";
import AppErrorFallback from "app/frontend/components/error_handling/AppErrorFallback";
import { onRenderError } from "app/frontend/components/error_handling/utils";
import { createRoot } from "react-dom/client";
import type { ComponentType } from "react";
import { logDev } from "app/frontend/sway_utils";
import PublicApp from "app/frontend/PublicApp";
import { resolvePageLoader } from "app/frontend/pageResolver";

const pages = import.meta.glob([
    "../pages/public/**/*.tsx",
    "!../pages/public/**/__tests__/**",
    "!../pages/public/**/*.test.tsx",
]) as Record<string, any>;

type InertiaPageComponent = ComponentType<any>;

document.addEventListener("DOMContentLoaded", () => {
    const Sentry = import("@sentry/react");

    createInertiaApp({
        resolve: async (_pageName: string) => {
            const { loader, pageName } = resolvePageLoader(_pageName, pages);

            logDev("public.tsx - createInertiaApp - page pageName -", pageName);

            return Promise.resolve(loader()).then((_page) => {
                const page = ((_page as { default?: InertiaPageComponent }).default ??
                    (_page as InertiaPageComponent | undefined)) as InertiaPageComponent | undefined;

                if (!page) {
                    throw new Error(`Unable to resolve public Inertia page "${pageName}".`);
                }

                return page;
            });
        },

        setup({ el, App: InertiaApp, props }) {
            Sentry.then(({ ErrorBoundary: SentryErrorBoundary }) => {
                createRoot(el!).render(
                    <SentryErrorBoundary onError={onRenderError} fallback={<AppErrorFallback />}>
                        <PublicApp>
                            <InertiaApp {...props} />
                        </PublicApp>
                    </SentryErrorBoundary>,
                );
            }).catch(console.error);
        },
    }).catch(console.error);
});
