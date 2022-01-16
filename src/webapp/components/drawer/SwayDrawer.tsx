/** @format */
import { Circle } from "@mui/icons-material";
import { Avatar, Box, SvgIconTypeMap } from "@mui/material";
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
import { ROUTES, SWAY_USER_REGISTERED } from "src/constants";
import { isEmptyObject, logDev, removeStorage } from "src/utils";
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
    children: React.ReactNode;
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

    const getMenuComponent = (
        text: string | React.ReactNode,
        Icon?: OverridableComponent<
            SvgIconTypeMap<Record<string, unknown>, "svg">
        >,
    ) => {
        logDev("SwayDrawer.getMenuComponent - Return title with text -", text);
        return (
            <div className="row align-items-center">
                <div className="col-10 fw-bold pe-0">{text}</div>
                {Icon && (
                    <div className="col-2 text-start">
                        <Icon />
                    </div>
                )}
            </div>
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
            return getMenuComponent(menuChoices[0].text, menuChoices[0].Icon);
        }
        return getMenuComponent(item.text, item.Icon);
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

    const isSelected = (route: string) => {
        return route === pathname;
    };

    const getOnClick = (item: MenuItem) => {
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

    const getIcon = useCallback((item: MenuItem) => {
        if (item.route === "invite") {
            return (
                <item.Icon user={user} withText={!IS_MOBILE_PHONE || open} />
            );
        } else {
            return <item.Icon user={user} />;
        }
    }, []);

    const getListItem = useCallback(
        (item: MenuItem, index: number) => {
            if (item.route === "invite") {
                return (
                    <item.Icon
                        key={item.route + index}
                        user={user}
                        withText={!IS_MOBILE_PHONE || open}
                    />
                );
            }
            return (
                <ListItem
                    key={item.route + index}
                    selected={isSelected(item.route)}
                    onClick={() => getOnClick(item)}
                    className="row px-0"
                    button
                >
                    <ListItemIcon
                        className="col-2 pe-0"
                        style={{ minWidth: 0 }}
                    >
                        {getIcon(item)}
                    </ListItemIcon>
                    {item.route ? (
                        <ListItemText className="col-9 px-0">
                            {item.text}
                        </ListItemText>
                    ) : (
                        <ListItemText
                            className="col-9 px-0"
                            primary={item.text}
                        />
                    )}
                    {isSelected(item.route) ? (
                        <ListItemIcon
                            className="col-1 px-0"
                            style={{ minWidth: 0 }}
                        >
                            <Circle className="fs-6" />
                        </ListItemIcon>
                    ) : null}
                </ListItem>
            );
        },
        [pathname],
    );

    const sx = !IS_MOBILE_PHONE
        ? { width: `calc(100% - ${DRAWER_WIDTH}px)`, ml: `${DRAWER_WIDTH}px` }
        : undefined;
    return (
        <Box className="d-flex">
            <Box>
                <AppBar ref={ref} position="fixed" sx={sx}>
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
                    role="nav"
                    anchor="left"
                    open={open}
                    variant={IS_MOBILE_PHONE ? "temporary" : "permanent"}
                    ModalProps={{
                        keepMounted: true, // Better open performance on mobile.
                    }}
                    sx={{
                        width: DRAWER_WIDTH,
                        "& .MuiDrawer-paper": {
                            width: DRAWER_WIDTH,
                            boxSizing: "border-box",
                        },
                    }}
                >
                    <Box className="p-2">
                        <DefaultMenuTitle />
                    </Box>
                    <List className="pt-2">{menuChoices.map(getListItem)}</List>
                    {!isEmptyObject(bottomMenuChoices) && (
                        <List>{bottomMenuChoices.map(getListItem)}</List>
                    )}
                    <SocialIconsList />
                </Drawer>
            </Box>
            <Box component="main" className="container mt-5 pt-4">
                {props.children}
            </Box>
        </Box>
    );
};

export default SwayDrawer;
