import { ToastProps } from "react-toastify";
import { Typography } from "@material-ui/core";

const SwayToast = ({
    toastProps,
    title,
    message,
}: {
    closeToast: () => void;
    toastProps: ToastProps;
    title?: string;
    message: string;
}) => {
    console.log({toastProps});

    return (
        <div>
            {title && <Typography gutterBottom variant={"body1"} style={{ fontWeight: 700 }}>{title}</Typography>}
            <Typography gutterBottom variant={"body2"} style={{ fontWeight: 700 }}>{message}</Typography>
        </div>
    );
};

export default SwayToast;
