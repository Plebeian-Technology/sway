/** @format */
import { withStyles } from "@mui/styles";

import { Theme, Tooltip } from "@mui/material";
import { swayWhite } from "../utils";

const HtmlTooltip = withStyles((theme: Theme) => ({
    tooltip: {
        backgroundColor: theme.palette.primary.main,
        border: `2px solid ${swayWhite}`,
        borderRadius: theme.spacing(2),
        padding: theme.spacing(3),
        textAlign: "center",
    },
}))(Tooltip);

export default HtmlTooltip;
