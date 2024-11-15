import SwayLogo from "app/frontend/components/SwayLogo";
import axios from "axios";
import { useEffect, useState } from "react";
import { Button } from "react-bootstrap";

const STYLE = {
    width: "100%",
    height: "100%",
    minHeight: "100vh",
    display: "flex",
    flexDirection: "column",
    alignItems: "center",
    justifyContent: "center",
    textAlign: "center",
    margin: "0 auto",
} as React.CSSProperties;

const getCookies = () =>
    document.cookie.split(";").reduce((sum, kvString) => {
        const [key, value] = kvString.split("=");
        return {
            ...sum,
            [key.trim()]: value.trim(),
        };
    }, {}) as Record<string, string>;

const handleLogOut = () => {
    const csrfToken =
        (document.querySelector("meta[name=csrf-token]") as HTMLMetaElement | undefined)?.content ||
        getCookies()["XSRF-TOKEN"];

    axios
        .delete("/users/webauthn/sessions/0", {
            headers: {
                "X-CSRF-Token": csrfToken,
            },
        })
        .finally(window.location.reload);
};

const ErrorBoundary = () => {
    const [seconds, setSeconds] = useState<number>(60);

    useEffect(() => {
        let timer: number | undefined;

        if (seconds === 0) {
            if (window.location.pathname === "/") {
                try {
                    localStorage.clear();
                    sessionStorage.clear();
                } catch (error) {
                    console.warn(error);
                }
                window.location.reload();
            } else {
                window.location.href = "/";
            }
        } else {
            timer = window.setTimeout(() => {
                setSeconds(seconds - 1);
            }, 1000);
        }

        return () => {
            if (timer) {
                window.clearTimeout(timer);
            }
        };
    }, [seconds]);

    return (
        <div style={STYLE}>
            <SwayLogo />
            <div className="mt-2">Sway had an issue loading the page.</div>
            <div className="mt-2">
                Resetting and reloading Sway in <span className="bold">{seconds}</span> seconds.
            </div>
            <div className="mt-5">Try refreshing the page first but if this issue persists try to:</div>
            <div className="mt-1">
                <Button onClick={handleLogOut}>Log Out</Button>
            </div>
        </div>
    );
};

export default ErrorBoundary;
