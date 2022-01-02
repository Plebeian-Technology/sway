import { ToastProps } from "react-toastify";
import { makeStyles } from "@mui/styles";
import { Typography } from "@mui/material";

const useStyles = makeStyles({
    text: {
        fontWeight: 700,
    },
});

const SwayToast = ({
    title,
    message,
    tada,
}: {
    closeToast: () => void;
    toastProps: ToastProps;
    title: string;
    tada: boolean;
    message?: string;
}) => {
    const classes = useStyles({ tada });
    return (
        <div>
            <Typography gutterBottom variant={"body1"} className={classes.text}>
                {title}
            </Typography>
            {message && (
                <Typography
                    gutterBottom
                    variant={"body2"}
                    className={classes.text}
                >
                    {message}
                </Typography>
            )}
        </div>
    );
};

export default SwayToast;
