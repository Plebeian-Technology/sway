import { PropsWithChildren, StrictMode, useLayoutEffect } from "react";
import { Toaster } from "react-hot-toast";

const SwayApp: React.FC<PropsWithChildren> = ({ children }) => {
    useLayoutEffect(() => {
        document.getElementById("application-loading")?.style.setProperty("display", "none");
    }, []);

    return (
        <StrictMode>
            {children}
            <Toaster />
        </StrictMode>
    );
};

export default SwayApp;
