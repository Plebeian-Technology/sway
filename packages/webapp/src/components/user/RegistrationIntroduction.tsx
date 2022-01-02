/** @format */
import { makeStyles } from "@mui/styles";

import { Button, Divider, Link, Theme, Typography } from "@mui/material";
import { HowToReg } from "@mui/icons-material";
import { ROUTES } from "@sway/constants";
import React from "react";
import { useHistory } from "react-router-dom";
import { sway } from "sway";
import { swayBlack, swayGray, swayLightBlue, swayWhite } from "../../utils";
import SwaySvg from "../SwaySvg";

const useStyles = makeStyles((theme: Theme) => ({
    banner: {
        borderBottom: `3px solid ${swayGray}`,
        letterSpacing: 0,
    },
    button: {
        padding: theme.spacing(2),
        margin: theme.spacing(1),
        backgroundColor: swayLightBlue,
        color: swayWhite,
    },
    buttonContainer: {
        textAlign: "center",
    },
    textContainer: {
        display: "flex",
        flexDirection: "column",
        margin: theme.spacing(1),
        padding: theme.spacing(1),
    },
    typography: {
        margin: theme.spacing(1),
    },
    link: {
        color: swayBlack,
        fontWeight: "bold",
    },
}));

interface IProps {
    user: sway.IUser | undefined;
}

const RegistrationIntroduction: React.FC<IProps> = () => {
    const classes = useStyles();
    const history = useHistory();
    const [isLoadingComponent, setLoadingComponent] =
        React.useState<boolean>(true);

    React.useEffect(() => {
        setLoadingComponent(false);
    }, [setLoadingComponent]);

    const handleGoToRegistration = () => {
        history.push(ROUTES.registration);
    };

    return (
        <div className={"registration-container"}>
            <div id="subcontainer">
                <div className={classes.textContainer}>
                    <Typography
                        className={classes.typography}
                        component="h6"
                        variant="h6"
                    >
                        Sway requires additional information about you in order
                        to match you with your representatives.
                    </Typography>
                    <Typography
                        className={classes.typography}
                        component="h6"
                        variant="h6"
                    >
                        We take privacy very seriously. If you have any
                        questions about what happens to your data please see our
                        privacy policy, or contact our internal privacy auditor
                        at{" "}
                        <Link
                            className={classes.link}
                            href="mailto:privacy@sway.vote"
                        >
                            privacy@sway.vote
                        </Link>
                        .
                    </Typography>
                    <Typography
                        className={classes.typography}
                        component="h6"
                        variant="h6"
                    >
                        We also offer virtual walkthroughs of Sway, showcasing
                        where and how your data is stored. To schedule a
                        walkthrough send an email to{" "}
                        <Link
                            className={classes.link}
                            href="mailto:privacy@sway.vote"
                        >
                            privacy@sway.vote
                        </Link>
                        .
                    </Typography>
                    {/* <Typography
                                    className={classes.typography}
                                    component="p"
                                    variant="body1"
                                    color="textPrimary"
                                >
                                    If you want to see more about how Sway
                                    works under-the-hood, code for Sway is
                                    open-source and publicly viewable and
                                    editable on Github at{" "}
                                    <Link className={classes.link} href="https://www.github.com/plebeian-technologies/sway">
                                        https://www.github.com/plebeian-technologies/sway
                                    </Link>
                                    .
                                </Typography> */}
                </div>
                <Divider />
                <div className={classes.textContainer}>
                    <Typography
                        className={classes.typography}
                        style={{ marginTop: 1, marginBottom: 1 }}
                        component="h6"
                        variant="h6"
                    >
                        If you are registered to vote, please complete each of
                        the following fields to match, as closely as possible,
                        what is on your voter registration.
                    </Typography>
                    <Typography
                        className={classes.typography}
                        style={{ marginTop: 1, marginBottom: 1 }}
                        component="h6"
                        variant="h6"
                    >
                        If you are not registered to vote, it is not required
                        but is{" "}
                        <span style={{ fontWeight: "bold" }}>strongly</span>{" "}
                        recommended. You can register to vote
                        <Link
                            className={classes.link}
                            target={"_blank"}
                            href="https://www.vote.org/register-to-vote/"
                        >
                            {" here."}
                        </Link>
                    </Typography>
                    <Typography
                        className={classes.typography}
                        style={{ marginTop: 1, marginBottom: 1 }}
                        component="h6"
                        variant="h6"
                    >
                        You can find your current voter registration
                        <Link
                            className={classes.link}
                            target={"_blank"}
                            href="https://www.vote.org/am-i-registered-to-vote/"
                        >
                            {" here."}
                        </Link>
                    </Typography>
                </div>
                <Divider />
                <div className={classes.textContainer}>
                    <Typography
                        className={classes.typography}
                        style={{ marginTop: 1, marginBottom: 1 }}
                        component="h6"
                        variant="h6"
                    >
                        If you want to see more about how Sway works
                        under-the-hood, code for Sway is available on{" "}
                        {
                            <Button
                                disabled={isLoadingComponent}
                                className={classes.button}
                                style={{ padding: "0.5em 1em", margin: 0 }}
                                variant="contained"
                                color="primary"
                                onClick={() =>
                                    window.open(
                                        "https://github.com/Plebeian-Technology/sway",
                                    )
                                }
                                startIcon={
                                    <SwaySvg
                                        src={"/icons/github.svg"}
                                        containerStyle={{ margin: "0px" }}
                                    />
                                }
                            >
                                {"Github"}
                            </Button>
                        }
                    </Typography>
                </div>
                <div className={classes.buttonContainer}>
                    <Button
                        disabled={isLoadingComponent}
                        className={classes.button}
                        variant="contained"
                        color="primary"
                        onClick={handleGoToRegistration}
                        startIcon={<HowToReg />}
                    >
                        {"Complete Sway Registration"}
                    </Button>
                </div>
            </div>
        </div>
    );
};

export default RegistrationIntroduction;
