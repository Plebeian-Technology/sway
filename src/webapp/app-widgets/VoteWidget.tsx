import { Button } from "@mui/material";
import { makeStyles } from "@mui/styles";
import { Check, Clear } from "@mui/icons-material";
import { Support } from "src/constants";
import { useState } from "react";
import FlexColumnDiv from "../components/shared/FlexColumnDiv";
import FlexRowDiv from "../components/shared/FlexRowDiv";
import { SWAY_COLORS } from "../utils";

const useStyles = makeStyles({
    button: () => ({
        width: 150,
        padding: "1em",
        margin: "1em",
        fontWeight: 700,
        border: "2px solid",
    }),
    for: ({ support }: { support: TSupport }) => ({
        color:
            support === Support.For ? SWAY_COLORS.white : SWAY_COLORS.success,
        backgroundColor:
            support === Support.For ? SWAY_COLORS.success : SWAY_COLORS.white,
        borderColor:
            support === Support.For ? SWAY_COLORS.white : SWAY_COLORS.success,
        "&:hover": {
            color: SWAY_COLORS.white,
            background: SWAY_COLORS.success,
        },
    }),
    against: ({ support }: { support: TSupport }) => ({
        color:
            support === Support.Against
                ? SWAY_COLORS.white
                : SWAY_COLORS.tertiary,
        backgroundColor:
            support === Support.Against
                ? SWAY_COLORS.tertiary
                : SWAY_COLORS.white,
        borderColor:
            support === Support.Against
                ? SWAY_COLORS.white
                : SWAY_COLORS.tertiary,
        "&:hover": {
            color: SWAY_COLORS.white,
            background: SWAY_COLORS.tertiary,
        },
    }),
});

type TSupport = "for" | "against" | null;

const VoteWidget = () => {
    const [support, setSupport] = useState<TSupport>(null);
    const classes = useStyles({ support });
    const handleVote = (voted: TSupport) => {
        setSupport(voted);
    };

    return (
        <FlexColumnDiv alignItems="center">
            <FlexRowDiv alignItems="center" justifyContent="center">
                <Button
                    classes={{
                        root: `${classes.button} ${classes.for}`,
                    }}
                    onClick={() => handleVote(Support.For as "for")}
                    startIcon={<Check />}
                >
                    {"For"}
                </Button>
                <img
                    src={"/sway-us-light.png"}
                    alt={"Sway"}
                    style={{ maxHeight: 50, maxWidth: 50 }}
                />
                <Button
                    classes={{
                        root: `${classes.button} ${classes.against}`,
                    }}
                    onClick={() => handleVote(Support.Against as "against")}
                    startIcon={<Clear />}
                >
                    {"Against"}
                </Button>
            </FlexRowDiv>
            {support && (
                <FlexRowDiv
                    alignItems="center"
                    justifyContent="center"
                    style={{ textAlign: "center" }}
                >
                    <span>
                        Empower your vote with{" "}
                        <a
                            style={{
                                textDecoration: "none",
                                color: SWAY_COLORS.primary,
                            }}
                            target="_blank"
                            href="https://app.sway.vote/bill-of-the-week?locale=baltimore_maryland_united-states"
                        >
                            Sway
                        </a>
                    </span>
                </FlexRowDiv>
            )}
        </FlexColumnDiv>
    );
};

export default VoteWidget;
