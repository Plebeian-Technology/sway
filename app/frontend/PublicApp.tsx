import { PropsWithChildren, StrictMode, useLayoutEffect } from "react";

// @lat: [[public-marketing-and-meta-pages#Why /sms, /privacy and /terms are Inertia pages under a second, minimal entrypoint]]
const PublicApp: React.FC<PropsWithChildren> = ({ children }) => {
    // @lat: [[app-boot-loading-screen-removal#Why App.tsx deletes the loading screen with useLayoutEffect]]
    useLayoutEffect(() => {
        document.getElementById("application-loading")?.remove();
    }, []);

    return <StrictMode>{children}</StrictMode>;
};

export default PublicApp;
