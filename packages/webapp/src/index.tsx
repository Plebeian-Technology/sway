/** @format */
import * as Sentry from "@sentry/react";
import { Integrations } from "@sentry/tracing";

import React from "react";
import ReactDOM from "react-dom";
import App from "./App";
import * as serviceWorker from "./serviceWorker";
import "./scss/main.scss";

if ("serviceWorker" in navigator) {
    const workerScript = process.env.NODE_ENV !== "production" ? "./firebase-messaging-sw-dev.js" : "./firebase-messaging-sw-prod.js"

    navigator.serviceWorker
        .register(workerScript)
        .then(function (registration) {
            console.log("registered worker to scope: ", registration.scope);
        })
        .catch(function (err) {
            console.log("worker registration failed");
            if (process.env.NODE_ENV !== "production") {
                console.error(err);
            }
        });
}

if (process.env.NODE_ENV === "production") {
    Sentry.init({
        dsn: `https://${process.env.REACT_APP_SENTRY_IO_ENDPOINT}`,
        integrations: [new Integrations.BrowserTracing()],

        // We recommend adjusting this value in production, or using tracesSampler
        // for finer control
        tracesSampleRate: 1.0,
    });
}

ReactDOM.render(
    <React.StrictMode>
        <App />
    </React.StrictMode>,
    document.getElementById("root")
);

// If you want your app to work offline and load faster, you can change
// unregister() to register() below. Note this comes with some pitfalls.
// Learn more about service workers: https://bit.ly/CRA-PWA
serviceWorker.unregister();
