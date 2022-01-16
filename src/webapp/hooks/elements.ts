/** @format */

import { KEYCODE_ESC } from "src/constants";
import { logDev } from "src/utils";
import { useEffect, useLayoutEffect, useRef, useState } from "react";

export interface IDimensions {
    width: number;
    height: number;
}

export const useOpenCloseElement = (
    ref: React.RefObject<any>, // eslint-disable-line
    defaultState = false,
): [boolean, React.Dispatch<React.SetStateAction<boolean>>] => {
    const [open, setOpen] = useState<boolean>(defaultState);

    const handleClose = () => setOpen(false);

    const esc = (e: KeyboardEvent) => e.code === KEYCODE_ESC;
    const outside = (e: Event) =>
        ref.current && !ref.current.contains(e.target);

    const handleClick = (e: Event) => outside(e) && handleClose();
    const handleKeyDown = (e: KeyboardEvent) =>
        esc(e) && outside(e) && handleClose();

    useEffect(() => {
        document.addEventListener("click", handleClick);
        document.addEventListener("keydown", handleKeyDown);
        return () => {
            document.removeEventListener("click", handleClick);
            document.removeEventListener("keydown", handleKeyDown);
        };
    });

    return [open, setOpen];
};

export const useCloseElement = (): [
    boolean,
    React.Dispatch<React.SetStateAction<boolean>>,
] => {
    const [open, setOpen] = useState<boolean>(false);

    useEffect(() => {
        const handleClose = () => {
            setOpen(false);
        };

        const handleKeyDown = (event: KeyboardEvent) => {
            logDev("key down close");
            if (event.code === KEYCODE_ESC && open) handleClose();
        };

        document.addEventListener("keydown", handleKeyDown);
        return () => {
            document.removeEventListener("keydown", handleKeyDown);
        };
    }, [open]);

    return [open, setOpen];
};

export const useDimensions = (): [
    IDimensions,
    React.Dispatch<React.SetStateAction<IDimensions>>,
    React.RefObject<HTMLDivElement>,
] => {
    const containerRef = useRef<HTMLDivElement | null>(null);

    const [dimensions, setDimensions] = useState({
        width: 1200 / 3,
        height: 1200 / 4,
    });

    const offsetWidth = containerRef.current?.offsetWidth;

    useLayoutEffect(() => {
        if (containerRef.current) {
            setDimensions({
                width: Math.round(containerRef?.current?.offsetWidth) / 3,
                height: Math.round(containerRef?.current?.offsetWidth) / 4,
            });
        }
    }, [offsetWidth]);

    return [dimensions, setDimensions, containerRef];
};
