import { KEYCODE_ESC } from "app/frontend/sway_constants";
import { logDev } from "app/frontend/sway_utils";
import { useState, useEffect } from "react";

export const useCloseElement = (): [boolean, React.Dispatch<React.SetStateAction<boolean>>] => {
    const [open, setOpen] = useState<boolean>(false);

    useEffect(() => {
        const handleClose = () => {
            setOpen(false);
        };

        const handleKeyDown = (event: KeyboardEvent) => {
            logDev("useCloseElement.handleKeyDown - close");
            if (event.code === KEYCODE_ESC && open) handleClose();
        };

        document.addEventListener("keydown", handleKeyDown);
        return () => {
            document.removeEventListener("keydown", handleKeyDown);
        };
    }, [open]);

    return [open, setOpen];
};
