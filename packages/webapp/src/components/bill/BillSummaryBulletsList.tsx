import { Typography, useTheme } from "@material-ui/core";
import { Fragment } from "react";

const BillSummaryBulletsList: React.FC<{
    points: string[];
    klass: string | undefined;
}> = ({ points, klass }) => {
    const theme = useTheme();

    return (
        <ul style={{ marginTop: "1em" }}>
            {points.map((point: string, index: number) => {
                if (index === 0) {
                    const [intro, first] = point.split(":");
                    if (!first) {
                        return (
                            <li
                                key={index}
                                style={{ marginLeft: theme.spacing(3) }}
                            >
                                <Typography
                                    className={klass ? klass : ""}
                                    component={"span"}
                                    variant={"body1"}
                                    color="textPrimary"
                                >
                                    {point}
                                </Typography>
                            </li>
                        );
                    }
                    return (
                        <Fragment key={index}>
                            <Typography
                                className={klass ? klass : ""}
                                component={"span"}
                                variant={"body1"}
                                color="textPrimary"
                            >
                                {`${intro}:`}
                            </Typography>
                            <li
                                key={index}
                                style={{ marginLeft: theme.spacing(3) }}
                            >
                                <Typography
                                    className={klass ? klass : ""}
                                    component={"span"}
                                    variant={"body1"}
                                    color="textPrimary"
                                >
                                    {first}
                                </Typography>
                            </li>
                        </Fragment>
                    );
                }
                return (
                    <li key={index} style={{ marginLeft: theme.spacing(3) }}>
                        <Typography
                            className={klass ? klass : ""}
                            component={"span"}
                            variant={"body1"}
                            color="textPrimary"
                        >
                            {point}
                        </Typography>
                    </li>
                );
            })}
        </ul>
    );
};

export default BillSummaryBulletsList;
