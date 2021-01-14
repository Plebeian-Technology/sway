/** @format */

import React from "react";
import { KEYCODE_ESC } from "@sway/constants";
import { IS_DEVELOPMENT } from "../utils";

export interface IDimensions {
    width: number;
    height: number;
}

export const useOpenCloseElement = (
    ref: React.RefObject<any> // eslint-disable-line
): [boolean, React.Dispatch<React.SetStateAction<boolean>>] => {
    const [open, setOpen] = React.useState<boolean>(false);

    const handleClose = () => setOpen(false);

    const esc = (e: KeyboardEvent) => e.code === KEYCODE_ESC;
    const outside = (e: Event) =>
        ref.current && !ref.current.contains(e.target);

    const handleClick = (e: Event) => outside(e) && handleClose();
    const handleKeyDown = (e: KeyboardEvent) =>
        esc(e) && outside(e) && handleClose();

    React.useEffect(() => {
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
    React.Dispatch<React.SetStateAction<boolean>>
] => {
    const [open, setOpen] = React.useState<boolean>(false);

    React.useEffect(() => {
        const handleClose = () => {
            console.log("closing");
            setOpen(false);
        };

        const handleKeyDown = (event: KeyboardEvent) => {
            if (IS_DEVELOPMENT) console.log("key down close");
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
    React.RefObject<HTMLDivElement>
] => {
    const containerRef = React.useRef<HTMLDivElement | null>(null);

    const [dimensions, setDimensions] = React.useState({
        width: 1200 / 3,
        height: 1200 / 4,
    });

    const offsetWidth = containerRef.current?.offsetWidth;

    React.useLayoutEffect(() => {
        if (containerRef.current) {
            setDimensions({
                width: Math.round(containerRef?.current?.offsetWidth) / 3,
                height: Math.round(containerRef?.current?.offsetWidth) / 4,
            });
        }
    }, [offsetWidth]);

    return [dimensions, setDimensions, containerRef];
};
