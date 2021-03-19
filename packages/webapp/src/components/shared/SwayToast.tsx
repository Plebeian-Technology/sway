import { ToastProps } from "react-toastify";
import { createStyles, makeStyles, Typography } from "@material-ui/core";

const useStyles = makeStyles(() =>
    createStyles({
        text: {
            fontWeight: 700,
        },
    }),
);

const SwayToast = ({
    title,
    message,
    tada,
}: {
    closeToast: () => void;
    toastProps: ToastProps;
    title?: string;
    tada: boolean;
    message: string;
}) => {
    const classes = useStyles({ tada });
    return (
        <div>
            {title && (
                <Typography
                    gutterBottom
                    variant={"body1"}
                    className={classes.text}
                >
                    {title}
                </Typography>
            )}
            <Typography gutterBottom variant={"body2"} className={classes.text}>
                {message}
            </Typography>
        </div>
    );
};

export default SwayToast;
