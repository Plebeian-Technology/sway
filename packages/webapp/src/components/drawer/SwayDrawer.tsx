/** @format */
import { Avatar, SvgIconTypeMap } from "@mui/material";
import AppBar from "@mui/material/AppBar";
import Drawer from "@mui/material/Drawer";
import IconButton from "@mui/material/IconButton";
import List from "@mui/material/List";
import ListItem from "@mui/material/ListItem";
import ListItemIcon from "@mui/material/ListItemIcon";
import ListItemText from "@mui/material/ListItemText";
import { OverridableComponent } from "@mui/material/OverridableComponent";
import Toolbar from "@mui/material/Toolbar";
import Typography from "@mui/material/Typography";
import { ROUTES, SWAY_USER_REGISTERED } from "@sway/constants";
import { isEmptyObject, logDev, removeStorage } from "@sway/utils";
import React, { useCallback, useRef } from "react";
import { useLocation, useNavigate } from "react-router-dom";
import { sway } from "sway";
import { auth } from "../../firebase";
import { useOpenCloseElement } from "../../hooks";
import { handleError, IS_COMPUTER_WIDTH, IS_MOBILE_PHONE } from "../../utils";
import FlexRowDiv from "../shared/FlexRowDiv";
import SwaySvg from "../SwaySvg";
import SocialIconsList from "../user/SocialIconsList";

const DRAWER_WIDTH = 300;

type MenuItem = {
    route: string;
    Icon: OverridableComponent<SvgIconTypeMap<Record<string, unknown>, "svg">>;
    text: string | React.ReactNode;
};

interface IProps {
    menuChoices: MenuItem[];
    bottomMenuChoices: MenuItem[];
    user?: sway.IUser;
}

const DefaultMenuTitle: React.FC = () => (
    <FlexRowDiv alignItems="center">
        <Avatar src={"/logo300.png"} />
        &nbsp;
        <Typography variant={"h5"}>Sway</Typography>
    </FlexRowDiv>
);

const SwayDrawer: React.FC<IProps> = (props) => {
    const navigate = useNavigate();
    const location = useLocation();
    const ref = useRef<HTMLDivElement | null>(null);
    const [open, setOpen] = useOpenCloseElement(ref, !IS_MOBILE_PHONE);

    const handleDrawerOpen = useCallback(() => setOpen(true), [setOpen]);

    const { user, menuChoices, bottomMenuChoices } = props;
    const pathname = location.pathname;

    const _menuTitle = (
        text: string | React.ReactNode,
        Icon?: OverridableComponent<
            SvgIconTypeMap<Record<string, unknown>, "svg">
        >,
    ) => {
        logDev("SwayDrawer._menuTitle - Return title with text -", text);
        return (
            <FlexRowDiv alignItems="center">
                {text}&nbsp;
                {Icon && <Icon />}
            </FlexRowDiv>
        );
    };

    const menuTitle = () => {
        if (!IS_MOBILE_PHONE && IS_COMPUTER_WIDTH) {
            logDev(
                "SwayDrawer.menuTitle - NOT mobile phone. Return default menu title",
            );
            return <DefaultMenuTitle />;
        }

        const title = (location?.state as sway.IPlainObject)?.title;
        logDev("SwayDrawer.menuTitle - ", title);
        if (title) {
            return title;
        }

        const item: MenuItem | undefined = menuChoices.find(
            (mc: MenuItem) => mc.route === pathname,
        );
        if (!item) {
            if (!menuChoices[0]) {
                logDev(
                    "SwayDrawer.menuTitle - NO menu choices. Return default menu title",
                );
                return <DefaultMenuTitle />;
            }
            return _menuTitle(menuChoices[0].text, menuChoices[0].Icon);
        }
        return _menuTitle(item.text, item.Icon);
    };

    const handleNavigate = (route: string, state?: sway.IPlainObject) => {
        logDev("Navigating to route -", route);

        if (route === ROUTES.signin) {
            window.location.href = "/";
        } else if (state) {
            navigate(route, state);
        } else {
            navigate(route);
        }
    };

    const handleBottomMenuClick = (item: MenuItem) => {
        if (item.route === "invite") return;

        if (item.route === ROUTES.logout) {
            auth.signOut()
                .then(() => {
                    removeStorage(SWAY_USER_REGISTERED);
                    window.location.href = "/";
                })
                .catch(handleError);
        } else {
            handleNavigate(item.route, { title: item.text });
        }
    };

    const isSelected = (route: string) => {
        return route === pathname;
    };

    return (
        <>
            <AppBar ref={ref} position="static">
                <Toolbar className="pointer" onClick={handleDrawerOpen}>
                    {IS_MOBILE_PHONE && (
                        <IconButton
                            color="inherit"
                            aria-label="open drawer"
                            edge="start"
                            className={"p-0"}
                        >
                            <SwaySvg src={"/menu.svg"} />
                        </IconButton>
                    )}
                    {menuTitle()}
                </Toolbar>
            </AppBar>
            <Drawer
                anchor="left"
                open={open}
                variant={IS_COMPUTER_WIDTH ? "temporary" : "persistent"}
                ModalProps={{
                    keepMounted: IS_MOBILE_PHONE, // Better open performance on mobile.
                }}
                sx={{
                    display: { xs: "block", sm: "none" },
                    "& .MuiDrawer-paper": {
                        boxSizing: "border-box",
                        width: DRAWER_WIDTH,
                    },
                }}
            >
                <div className="p-2">
                    <DefaultMenuTitle />
                </div>
                <List className="pt-2">
                    {menuChoices.map((item: MenuItem, index: number) => (
                        <ListItem
                            key={item.route + index}
                            className={
                                isSelected(item.route)
                                    ? "bg-primary text-light"
                                    : ""
                            }
                            onClick={() => handleNavigate(item.route)}
                        >
                            <ListItemIcon
                                className={
                                    isSelected(item.route)
                                        ? "bg-primary text-light"
                                        : ""
                                }
                            >
                                <item.Icon />
                            </ListItemIcon>
                            {item.route ? (
                                <ListItemText>{item.text}</ListItemText>
                            ) : (
                                <ListItemText primary={item.text} />
                            )}
                        </ListItem>
                    ))}
                </List>
                {!isEmptyObject(bottomMenuChoices) && (
                    <>
                        <List>
                            {bottomMenuChoices.map(
                                (item: MenuItem, index: number) => (
                                    <ListItem
                                        key={item.route + index}
                                        className={
                                            isSelected(item.route)
                                                ? "bg-primary text-light"
                                                : ""
                                        }
                                        onClick={() =>
                                            handleBottomMenuClick(item)
                                        }
                                    >
                                        <ListItemIcon
                                            className={
                                                isSelected(item.route)
                                                    ? "bg-primary text-light"
                                                    : ""
                                            }
                                        >
                                            {item.route === "invite" ? (
                                                <item.Icon
                                                    user={user}
                                                    withText={
                                                        !IS_MOBILE_PHONE || open
                                                    }
                                                />
                                            ) : (
                                                <item.Icon user={user} />
                                            )}
                                        </ListItemIcon>
                                        <ListItemText primary={item.text} />
                                    </ListItem>
                                ),
                            )}
                        </List>
                    </>
                )}
                <SocialIconsList />
            </Drawer>
        </>
    );
};

export default SwayDrawer;
