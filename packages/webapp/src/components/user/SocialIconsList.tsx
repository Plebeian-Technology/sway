import { List, ListItem, ListItemIcon, ListItemText } from "@material-ui/core";
import SwaySvg from "../SwaySvg";

const SocialIconsList = () => (
    <List>
        <ListItem
            button
            onClick={() => window.open("https://twitter.com/Sway_Vote")}
        >
            <ListItemIcon>
                <SwaySvg
                    src={"/icons/twitter.svg"}
                    containerStyle={{ margin: "0px" }}
                />
            </ListItemIcon>
            <ListItemText primary={"Twitter"} />
        </ListItem>
        <ListItem
            button
            onClick={() =>
                window.open("https://github.com/Plebeian-Technology/sway")
            }
        >
            <ListItemIcon>
                <SwaySvg
                    src={"/icons/github.svg"}
                    containerStyle={{ margin: "0px" }}
                />
            </ListItemIcon>
            <ListItemText primary={"Github"} />
        </ListItem>
    </List>
);

export default SocialIconsList;
