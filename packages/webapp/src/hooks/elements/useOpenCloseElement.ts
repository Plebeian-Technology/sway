/** @format */

import { KEYCODE_ESC } from "@sway/constants";
import { useCallback, useEffect, useState } from "react";

export interface IDimensions {
    width: number;
    height: number;
}

export const useOpenCloseElement = (
    ref: React.RefObject<any>, // eslint-disable-line
    defaultState = false,
): [boolean, React.Dispatch<React.SetStateAction<boolean>>] => {
    const [open, setOpen] = useState<boolean>(defaultState);

    const handleClose = useCallback(() => setOpen(false), []);

    const esc = useCallback((e: KeyboardEvent) => e.code === KEYCODE_ESC, []);
    const outside = useCallback(
        (e: Event) => ref.current && !ref.current.contains(e.target),
        [ref],
    );

    const handleClick = useCallback(
        (e: Event) => outside(e) && handleClose(),
        [outside, handleClose],
    );
    const handleKeyDown = useCallback(
        (e: KeyboardEvent) => esc(e) && outside(e) && handleClose(),
        [esc, outside, handleClose],
    );

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
