// @lat: [[error-boundary-hierarchy#App-level: the Sentry boundary]]
import SwayLogo from "app/frontend/components/SwayLogo";
import { router } from "@inertiajs/react";
import { useEffect, useState } from "react";
import { Button } from "app/frontend/components/ui/button";

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

const handleLogOut = () => {
    try {
        localStorage.clear();
        sessionStorage.clear();
    } catch (error) {
        console.warn(error);
    }
    router.delete("/users/webauthn/sessions/0", {
        onFinish: () => window.location.reload(),
    });
};

const AppErrorFallback: React.FC = () => {
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

export default AppErrorFallback;
