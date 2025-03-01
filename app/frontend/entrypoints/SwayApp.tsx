import { PropsWithChildren, StrictMode, useEffect, useLayoutEffect } from "react";
import { Toaster } from "react-hot-toast";

// ! NOTE: Using partial reloads in a useEffect may be a good substitute - https://inertiajs.com/partial-reloads
// Inertia.js with back button history
// https://github.com/inertiajs/inertia/issues/565#issuecomment-895225604
// let stale = false;
// router.on("navigate", (event) => {
//     const page = event.detail.page;
//     if (stale) {
//         router.get(page.url, {}, { replace: true, preserveState: false, preserveScroll: true });
//     }
//     stale = false;
// });

// Add to Component below:
// useEffect(() => {
//     const handler = (event: PopStateEvent) => {
//         event.stopImmediatePropagation();
//         stale = true;
//     };

//     window.addEventListener("popstate", handler);
//     return () => {
//         window.removeEventListener("popstate", handler);
//     };
// }, []);

const SwayApp: React.FC<PropsWithChildren> = ({ children }) => {
    useLayoutEffect(() => {
        document.getElementById("application-loading")?.style.setProperty("display", "none");
    }, []);

    useEffect(() => {
        // Redirect to app.sway.vote if a user is using Firefox because of how Firefox handles
        // related origin webauthn requests
        // https://web.dev/articles/webauthn-related-origin-requests
        // https://github.com/w3c/webauthn/wiki/Explainer:-Related-origin-requests
        // https://github.com/mozilla/standards-positions/issues/1052
        const isFirefox = typeof navigator !== "undefined" && navigator.userAgent.toLowerCase().indexOf("firefox") > -1;
        if (isFirefox && window.location.hostname === "sway.vote") {
            window.location.href = "https://app.sway.vote";
        }
    }, []);

    return (
        <StrictMode>
            {children}
            <Toaster />
        </StrictMode>
    );
};

export default SwayApp;
