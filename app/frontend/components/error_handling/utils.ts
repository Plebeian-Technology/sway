
import { captureException } from "@sentry/react";
import { notify } from "app/frontend/sway_utils";
import axios from "axios";

export const onRenderError = (e: unknown) => {
    const error = e as Error
    console.warn("React/Sentry Error Boundary Handler - onRenderError");

    if (import.meta.env.MODE === "development") {
        return;
    }

    if (
        error?.message?.includes("Failed to fetch dynamically imported module") ||
        error?.message?.includes("Importing a module script failed")
    ) {
        window.location.reload();
        return;
    }

    if (error?.message?.toLowerCase()?.includes("operation is insecure")) {
        notify({
            level: "error",
            title: "Sway requires cookies be enabled in order for certain features to function properly.",
        });
        return;
    }

    captureException(error, { extra: { sway: "Error occurred in onRenderError" } });

    try {
        document.cookie = "";
    } catch (e) {
        console.warn(e);
    }

    try {
        sessionStorage?.clear();
    } catch (e) {
        console.warn(e);
    }

    try {
        localStorage?.clear();
    } catch (e) {
        console.warn(e);
    }

    if ("caches" in window) {
        caches
            .keys()
            .then((names) => names.forEach(async (name) => await caches.delete(name)))
            .catch(console.error);
    }

    axios.delete("/users/webauthn/sessions/0").catch(console.warn);
};
