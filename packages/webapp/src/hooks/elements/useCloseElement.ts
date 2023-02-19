import { KEYCODE_ESC } from "@sway/constants";
import { logDev } from "@sway/utils";
import { useState, useEffect } from "react";

export const useCloseElement = (): [boolean, React.Dispatch<React.SetStateAction<boolean>>] => {
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
