/** @format */
import * as Sentry from "@sentry/react";
import { BrowserTracing } from "@sentry/tracing";

import { IS_PRODUCTION } from "@sway/utils";
import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import App from "../App";
import * as serviceWorker from "../serviceWorker";
import { IS_TAURI } from "../utils";

if (IS_PRODUCTION) {
    try {
        Sentry.init({
            dsn: "https://acbcbf733d2a472fafd3da8c4513d9c3@o4503996405907456.ingest.sentry.io/4503996406562816",
            integrations: [new BrowserTracing()],

            // Set tracesSampleRate to 1.0 to capture 100%
            // of transactions for performance monitoring.
            // We recommend adjusting this value in production
            tracesSampleRate: 1.0,
        });
    } catch (error) {
        console.error("Failed to setup sentry.");
    }
}

if (!Array.prototype.first) {
    Array.prototype.first = function (defaultValue?: any) {
        return this[0] || defaultValue;
    };
}

if (!Array.prototype.last) {
    Array.prototype.last = function (defaultValue?: any) {
        return this[this.length - 1] || defaultValue;
    };
}

// React 18
createRoot(document.getElementById("root") as HTMLElement).render(
    <StrictMode>
        <App />
        {IS_TAURI ? null : <div id="recaptcha" />}
    </StrictMode>,
);

// If you want your app to work offline and load faster, you can change
// unregister() to register() below. Note this comes with some pitfalls.
// Learn more about service workers: https://bit.ly/CRA-PWA
serviceWorker.unregister();
