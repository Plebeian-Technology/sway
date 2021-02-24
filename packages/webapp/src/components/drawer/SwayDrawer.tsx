/** @format */

import { SvgIconTypeMap } from "@material-ui/core";
import AppBar from "@material-ui/core/AppBar";
import Drawer from "@material-ui/core/Drawer";
import IconButton from "@material-ui/core/IconButton";
import List from "@material-ui/core/List";
import ListItem from "@material-ui/core/ListItem";
import ListItemIcon from "@material-ui/core/ListItemIcon";
import ListItemText from "@material-ui/core/ListItemText";
import { OverridableComponent } from "@material-ui/core/OverridableComponent";
import {
    createStyles,
    makeStyles,
    Theme,
    useTheme,
} from "@material-ui/core/styles";
import Toolbar from "@material-ui/core/Toolbar";
import Typography from "@material-ui/core/Typography";
import ChevronLeftIcon from "@material-ui/icons/ChevronLeft";
import ChevronRightIcon from "@material-ui/icons/ChevronRight";
import { ROUTES } from "@sway/constants";
import { isEmptyObject, IS_DEVELOPMENT } from "@sway/utils";
import clsx from "clsx";
import React, { useCallback, useRef } from "react";
import { useHistory } from "react-router-dom";
import { sway } from "sway";
import BurgerMenuIcon from "../../assets/menu.svg";
import { auth } from "../../firebase";
import { useOpenCloseElement } from "../../hooks";
import {
    handleError,
    IS_COMPUTER_WIDTH,
    IS_MOBILE_PHONE,
    IS_TABLET_PHONE_WIDTH,
    swayWhite,
    SWAY_COLORS,
} from "../../utils";
import SwaySvg from "../SwaySvg";
import SocialIconsList from "../user/SocialIconsList";

const DRAWER_WIDTH = 240;

const useStyles = makeStyles((theme: Theme) =>
    createStyles({
        content: {
            flexGrow: 1,
            transition: theme.transitions.create("margin", {
                easing: theme.transitions.easing.sharp,
                duration: theme.transitions.duration.leavingScreen,
            }),
        },
        contentShift: {
            transition: theme.transitions.create("margin", {
                easing: theme.transitions.easing.easeOut,
                duration: theme.transitions.duration.enteringScreen,
            }),
            marginLeft: 0,
        },
        appBar: {
            color: swayWhite,
            zIndex: theme.zIndex.drawer + 1,
            transition: theme.transitions.create(["margin", "width"], {
                easing: theme.transitions.easing.sharp,
                duration: theme.transitions.duration.leavingScreen,
            }),
        },
        appBarShift: {
            width: `calc(100% - ${DRAWER_WIDTH}px)`,
            marginLeft: DRAWER_WIDTH,
            transition: theme.transitions.create(["margin", "width"], {
                easing: theme.transitions.easing.easeOut,
                duration: theme.transitions.duration.enteringScreen,
            }),
        },
        menuTitle: {
            display: "flex",
            flexDirection: "row",
            alignItems: "center",
        },
        menuAvatar: {
            marginRight: theme.spacing(1),
        },
        menuButton: {
            padding: 0,
        },
        hide: {
            display: "none",
        },
        drawer: {
            width: DRAWER_WIDTH,
            flexShrink: 0,
            whiteSpace: "nowrap",
        },
        drawerOverride: {
            border: !IS_MOBILE_PHONE ? "none" : undefined,
        },
        drawerOpen: {
            width: DRAWER_WIDTH,
            transition: theme.transitions.create("width", {
                easing: theme.transitions.easing.sharp,
                duration: theme.transitions.duration.enteringScreen,
            }),
        },
        drawerClose: {
            transition: theme.transitions.create("width", {
                easing: theme.transitions.easing.sharp,
                duration: theme.transitions.duration.leavingScreen,
            }),
            overflowX: "hidden",
            width: theme.spacing(7) + 1,
        },
        drawerPaper: {
            width: DRAWER_WIDTH,
        },
        drawerHeader: {
            display: "flex",
            alignItems: "center",
            padding: theme.spacing(0, 1),
            // necessary for content to be below app bar
            ...theme.mixins.toolbar,
            justifyContent: "flex-end",
        },
        drawerSelected: {
            color: SWAY_COLORS.white,
            backgroundColor: SWAY_COLORS.primary,
            borderTopRightRadius: 25,
            borderBottomRightRadius: 25,
        },
        drawerNotSelected: {
            cursor: "pointer",
        },
    }),
);

type MenuItem = {
    route: string;
    Icon: OverridableComponent<SvgIconTypeMap<Record<string, unknown>, "svg">>;
    text: string;
};

interface IProps {
    children: React.ReactNode;
    menuChoices: MenuItem[];
    bottomMenuChoices: MenuItem[];
    user?: sway.IUser;
}

const SwayDrawer: React.FC<IProps> = (props) => {
    const classes = useStyles();
    const theme = useTheme();
    const history = useHistory();
    const ref = useRef();
    const [open, setOpen] = useOpenCloseElement(ref, !IS_MOBILE_PHONE);

    const handleDrawerOpen = useCallback(() => setOpen(true), [setOpen]);
    const handleDrawerClose = useCallback(() => setOpen(!IS_MOBILE_PHONE), [
        setOpen,
    ]);

    const { user, menuChoices, bottomMenuChoices } = props;
    const pathname = history.location.pathname;

    const _menuTitle = (
        text: string,
        Icon?: OverridableComponent<
            SvgIconTypeMap<Record<string, unknown>, "svg">
        >,
    ) => {
        return (
            <div className={classes.menuTitle}>
                <span style={{ marginRight: 15 }}>{text}</span>
                {Icon && <Icon />}
            </div>
        );
    };

    const menuTitle = () => {
        const title = (history?.location?.state as sway.IPlainObject)?.title;
        if (title) {
            const menuItem = menuChoices
                .concat(bottomMenuChoices)
                .find((mc) => mc.text.toLowerCase() === title.toLowerCase());
            if (!menuItem) {
                return title;
            }
            return _menuTitle(menuItem.text, menuItem.Icon);
        }

        const item: MenuItem | undefined = menuChoices.find(
            (mc: MenuItem) => mc.route === pathname,
        );
        if (!item) {
            if (!menuChoices[0]) {
                return _menuTitle("Sway");
            }
            return _menuTitle(menuChoices[0].text, menuChoices[0].Icon);
        }
        return _menuTitle(item.text, item.Icon);
    };

    const handleNavigate = (route: string, state?: sway.IPlainObject) => {
        IS_DEVELOPMENT && console.log("(dev) Navigating to route -", route);

        if (route === ROUTES.signin) {
            window.location.href = "/";
        } else if (state) {
            history.push(route, state);
        } else {
            history.push(route);
        }
    };

    const handleBottomMenuClick = (item: MenuItem) => {
        if (item.route === "invite") return;

        if (item.route === ROUTES.logout) {
            auth.signOut()
                .then(() => {
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
        <div
            style={
                !IS_MOBILE_PHONE
                    ? {
                          display: "flex",
                      }
                    : { overflowX: "hidden" }
            }
        >
            <AppBar
                ref={ref}
                position="fixed"
                className={clsx(classes.appBar, {
                    [classes.appBarShift]: IS_MOBILE_PHONE ? open : false,
                })}
                style={{ boxShadow: "none" }}
            >
                <Toolbar
                    style={{ cursor: "pointer" }}
                    onClick={handleDrawerOpen}
                >
                    <IconButton
                        color="inherit"
                        aria-label="open drawer"
                        edge="start"
                        className={clsx(
                            classes.menuButton,
                            open && classes.hide,
                        )}
                    >
                        <SwaySvg src={BurgerMenuIcon} />
                    </IconButton>
                    <Typography variant="h6" noWrap>
                        {menuTitle() || "Sway"}
                    </Typography>
                </Toolbar>
            </AppBar>
            <Drawer
                variant={IS_COMPUTER_WIDTH ? "permanent" : "persistent"}
                className={clsx(classes.drawer, {
                    [classes.drawerOpen]: IS_MOBILE_PHONE ? open : true,
                    [classes.drawerClose]: IS_MOBILE_PHONE ? !open : false,
                })}
                classes={{
                    paper: clsx({
                        [classes.drawerOpen]: IS_MOBILE_PHONE ? open : true,
                        [classes.drawerClose]: IS_MOBILE_PHONE ? !open : false,
                    }),
                    paperAnchorDockedLeft: classes.drawerOverride,
                }}
                anchor="left"
                open={open}
                style={{
                    display: !open && IS_TABLET_PHONE_WIDTH ? "none" : "",
                }}
            >
                <div className={classes.drawerHeader}>
                    <Typography variant="h6" noWrap>
                        Sway
                    </Typography>
                    <IconButton onClick={handleDrawerClose}>
                        {theme.direction === "ltr" ? (
                            <ChevronLeftIcon />
                        ) : (
                            <ChevronRightIcon />
                        )}
                    </IconButton>
                </div>
                <List style={{ paddingTop: "4%" }}>
                    {menuChoices.map((item: MenuItem) => (
                        <ListItem
                            key={item.text}
                            className={
                                isSelected(item.route)
                                    ? classes.drawerSelected
                                    : classes.drawerNotSelected
                            }
                            onClick={() => handleNavigate(item.route)}
                        >
                            <ListItemIcon
                                classes={{
                                    root: isSelected(item.route)
                                        ? classes.drawerSelected
                                        : classes.drawerNotSelected,
                                }}
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
                            {bottomMenuChoices.map((item: MenuItem) => (
                                <ListItem
                                    key={item.text}
                                    className={
                                        isSelected(item.route)
                                            ? classes.drawerSelected
                                            : classes.drawerNotSelected
                                    }
                                    onClick={() => handleBottomMenuClick(item)}
                                >
                                    <ListItemIcon
                                        classes={{
                                            root: isSelected(item.route)
                                                ? classes.drawerSelected
                                                : classes.drawerNotSelected,
                                        }}
                                    >
                                        <item.Icon user={user} withText={!IS_MOBILE_PHONE || open} />
                                    </ListItemIcon>
                                    <ListItemText primary={item.text} />
                                </ListItem>
                            ))}
                        </List>
                    </>
                )}
                <SocialIconsList />
            </Drawer>
            <main
                className={clsx(classes.content, {
                    [classes.contentShift]: IS_MOBILE_PHONE ? open : true,
                })}
            >
                <div className={classes.drawerHeader} />
                {props.children}
            </main>
        </div>
    );
};

export default SwayDrawer;
