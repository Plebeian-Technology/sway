import { ListItemIcon } from "@mui/material";
import { Box } from "@mui/system";
import { GITHUB_LINK, TWITTER_LINK } from "@sway/constants";

const SocialIconsList = () => (
    <Box
        sx={{
            display: "flex",
            flexDirection: "row",
            justifyContent: "flex-start",
            width: "100%",
            pl: 2,
            pb: 2,
            mt: "auto",
        }}
    >
        <ListItemIcon onClick={() => window.open(TWITTER_LINK)}>
            <img width={30} src="/icons/twitter.svg" alt="navigate to Sway Twitter" />
        </ListItemIcon>
        <ListItemIcon onClick={() => window.open(GITHUB_LINK)}>
            <img width={30} src="/icons/github.svg" alt="navigate to Sway Github" />
        </ListItemIcon>
    </Box>
);

export default SocialIconsList;
