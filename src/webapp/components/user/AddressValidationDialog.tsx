/** @format */

import {
    Button,
    Dialog,
    DialogActions,
    DialogContent,
    DialogTitle,
    Theme,
    Typography,
} from "@mui/material";
import { sway } from "sway";
import CenteredLoading from "../dialogs/CenteredLoading";
import { IValidateResponseData } from "./Registration";
import { makeStyles } from "@mui/styles";
interface IAddressValidation {
    localeName: string;
    original: Partial<sway.IUser>;
    validated: IValidateResponseData;
}

interface IProps {
    cancel: () => void;
    confirm: ({ original, validated, localeName }: IAddressValidation) => void;
    original: Partial<sway.IUser>;
    validated: IValidateResponseData;
    localeName: string;
    isLoading: boolean;
    loadingMessage: string;
}

const useStyles = makeStyles((theme: Theme) => ({
    confirmContainer: {
        display: "flex",
        flexDirection: "column",
    },
    textConfirmContainer: {
        marginBottom: theme.spacing(1),
    },
    textConfirm: {
        fontSize: theme.typography.fontSize * 1.5,
    },
}));

const AddressValidationDialog: React.FC<IProps> = ({
    confirm,
    cancel,
    original,
    validated,
    localeName,
    isLoading,
    loadingMessage,
}) => {
    const classes = useStyles();

    const handleConfirm = () => {
        confirm({
            original,
            validated,
            localeName,
        });
    };

    const handleCancel = () => {
        cancel();
    };

    return (
        <Dialog
            className={"hover-chart-dialog"}
            fullScreen={false}
            fullWidth={true}
            open={true}
            maxWidth={"xs"}
            onClose={cancel}
            aria-labelledby="address-validation-dialog"
        >
            <DialogTitle>
                {validated
                    ? "Confirm Your Address"
                    : "Error Validating Address"}
            </DialogTitle>
            <DialogContent>
                {isLoading && (
                    <CenteredLoading
                        textStyle={{
                            textAlign: "left",
                            margin: 5,
                            marginLeft: 0,
                        }}
                        message={loadingMessage}
                    />
                )}
                {validated && (
                    <div className={classes.confirmContainer}>
                        <div className={classes.textConfirmContainer}>
                            <Typography
                                className={classes.textConfirm}
                                variant="body1"
                                color="textPrimary"
                                component="p"
                            >
                                {"Address: "}
                            </Typography>
                            <Typography
                                className={classes.textConfirm}
                                variant="body2"
                                color="textSecondary"
                                component="p"
                            >
                                {validated.address1}
                            </Typography>
                        </div>
                        {validated.address2 && (
                            <div className={classes.textConfirmContainer}>
                                <Typography
                                    className={classes.textConfirm}
                                    variant="body1"
                                    color="textPrimary"
                                    component="p"
                                >
                                    {"Address 2: "}
                                </Typography>
                                <Typography
                                    className={classes.textConfirm}
                                    variant="body2"
                                    color="textSecondary"
                                    component="p"
                                >
                                    {validated.address2}
                                </Typography>
                            </div>
                        )}
                        <div className={classes.textConfirmContainer}>
                            <Typography
                                className={classes.textConfirm}
                                variant="body1"
                                color="textPrimary"
                                component="p"
                            >
                                {"City: "}
                            </Typography>
                            <Typography
                                className={classes.textConfirm}
                                variant="body2"
                                color="textSecondary"
                                component="p"
                            >
                                {validated.city}
                            </Typography>
                        </div>
                        <div className={classes.textConfirmContainer}>
                            <Typography
                                className={classes.textConfirm}
                                variant="body1"
                                color="textPrimary"
                                component="p"
                            >
                                {"State: "}
                            </Typography>
                            <Typography
                                className={classes.textConfirm}
                                variant="body2"
                                color="textSecondary"
                                component="p"
                            >
                                {validated.region}
                            </Typography>
                        </div>
                        <div className={classes.textConfirmContainer}>
                            <Typography
                                className={classes.textConfirm}
                                variant="body1"
                                color="textPrimary"
                                component="p"
                            >
                                {"Zip Code: "}
                            </Typography>
                            <Typography
                                className={classes.textConfirm}
                                variant="body2"
                                color="textSecondary"
                                component="p"
                            >
                                {validated.postalCode}
                            </Typography>
                        </div>
                        <div className={classes.textConfirmContainer}>
                            <Typography
                                className={classes.textConfirm}
                                variant="body1"
                                color="textPrimary"
                                component="p"
                            >
                                {"Zip +4: "}
                            </Typography>
                            <Typography
                                className={classes.textConfirm}
                                variant="body2"
                                color="textSecondary"
                                component="p"
                            >
                                {validated.postalCodeExtension}
                            </Typography>
                        </div>
                    </div>
                )}
                {!validated && (
                    <>
                        <Typography
                            variant="body2"
                            color="textPrimary"
                            component="p"
                        >
                            No worries, just keep going and we'll figure it out
                            later.
                        </Typography>
                    </>
                )}
            </DialogContent>
            <DialogActions>
                <Button onClick={handleCancel} color="secondary">
                    Cancel
                </Button>
                <Button
                    onClick={handleConfirm}
                    color="primary"
                    disabled={isLoading}
                >
                    {validated ? "Confirm" : "Okay"}
                </Button>
            </DialogActions>
        </Dialog>
    );
};

export default AddressValidationDialog;