import { useEffect } from "react";
import { router } from "@inertiajs/react";

// @lat: [[bill-page-polling-props-rationale#What useActionCableReconnect adds beyond ActionCable's own reconnect]]
export const useActionCableReconnect = (only: string[]): void => {
    useEffect(() => {
        const handleOnline = () => {
            router.reload({ only });
        };
        window.addEventListener("online", handleOnline);
        return () => {
            window.removeEventListener("online", handleOnline);
        };
    }, [only]);
};
