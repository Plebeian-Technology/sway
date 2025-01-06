import { PropsWithChildren, StrictMode } from "react";
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
    return (
        <StrictMode>
            {children}
            <Toaster />
        </StrictMode>
    );
};

export default SwayApp;
