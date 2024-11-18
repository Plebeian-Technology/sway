import { router } from "@inertiajs/react";
import { PropsWithChildren, StrictMode, useEffect } from "react";
import { Toaster } from "react-hot-toast";

// Inertia.js with back button history
// https://github.com/inertiajs/inertia/issues/565#issuecomment-895225604
let stale = false;
router.on("navigate", (event) => {
    const page = event.detail.page;
    if (stale) {
        router.get(page.url, {}, { replace: true, preserveState: false, preserveScroll: true });
    }
    stale = false;
});

const SwayApp: React.FC<PropsWithChildren> = ({ children }) => {
    useEffect(() => {
        const handler = (event: PopStateEvent) => {
            event.stopImmediatePropagation();
            stale = true;
        };

        window.addEventListener("popstate", handler);
        return () => {
            window.removeEventListener("popstate", handler);
        };
    }, []);

    return (
        <StrictMode>
            {children}
            <Toaster />
        </StrictMode>
    );
};

export default SwayApp;
