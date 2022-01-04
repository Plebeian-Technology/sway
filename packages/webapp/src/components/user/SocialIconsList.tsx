import { List, ListItem, ListItemIcon, ListItemText } from "@mui/material";
import SwaySvg from "../SwaySvg";
import { GITHUB_LINK, TWITTER_LINK } from "@sway/constants";

const SocialIconsList = () => (
    <List>
        <ListItem button onClick={() => window.open(TWITTER_LINK)}>
            <ListItemIcon>
                <SwaySvg
                    src={"/icons/twitter.svg"}
                    containerStyle={{ margin: "0px" }}
                />
            </ListItemIcon>
            <ListItemText primary={"Sway Twitter"} />
        </ListItem>
        <ListItem button onClick={() => window.open(GITHUB_LINK)}>
            <ListItemIcon>
                <SwaySvg
                    src={"/icons/github.svg"}
                    containerStyle={{ margin: "0px" }}
                />
            </ListItemIcon>
            <ListItemText primary={"Sway Github"} />
        </ListItem>
    </List>
);

export default SocialIconsList;
