import { PropsWithChildren, StrictMode, useLayoutEffect } from "react";
import { Toaster } from "react-hot-toast";

import { ConfirmProvider } from "app/frontend/components/ui/confirm-dialog";

const App: React.FC<PropsWithChildren> = ({ children }) => {
    // @lat: [[app-boot-loading-screen-removal#Why App.tsx deletes the loading screen with useLayoutEffect]]
    useLayoutEffect(() => {
        document.getElementById("application-loading")?.remove();
    }, []);

    return (
        <StrictMode>
            <ConfirmProvider>
                <div className="min-h-svh text-foreground">
                    {children}
                    {/* @lat: [[toasts#Toast position is owned by the mounted Toaster]] */}
                    <Toaster position="top-right" />
                </div>
            </ConfirmProvider>
        </StrictMode>
    );
};

export default App;
