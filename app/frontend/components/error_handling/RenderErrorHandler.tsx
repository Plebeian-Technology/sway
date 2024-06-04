import { useEffect, useState } from "react";

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
} as const;

const RenderErrorHandler = () => {
    const [seconds, setSeconds] = useState<number>(60);

    useEffect(() => {
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
            setTimeout(() => {
                setSeconds(seconds - 1);
            }, 1000);
        }
    }, [seconds]);

    return (
        <div style={STYLE}>
            <div>Sway had an issue loading the page.</div>
            <div className="mt-2">Resetting and reloading Sway in {seconds} seconds.</div>
        </div>
    );
};

export default RenderErrorHandler;
