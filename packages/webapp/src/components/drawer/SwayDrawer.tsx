/** @format */
import { Circle } from "@mui/icons-material";
import { Avatar, CssBaseline, SvgIconTypeMap } from "@mui/material";
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
import { Box } from "@mui/system";
import { ROUTES, SWAY_USER_REGISTERED } from "@sway/constants";
import { isEmptyObject, logDev, removeStorage } from "@sway/utils";
import { signOut } from "firebase/auth";
import React, { useCallback, useEffect, useRef, useState } from "react";
import { useLocation, useNavigate } from "react-router-dom";
import { sway } from "sway";
import { auth } from "../../firebase";
import { useOpenCloseElement } from "../../hooks";
import { handleError, IS_MOBILE_PHONE } from "../../utils";
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
    <div className="row align-items-center w-100 p-1" style={{ maxWidth: 300 }}>
        <div className="col-2">
            <Avatar src={"/logo300.png"} />
        </div>
        <div className="col">
            <span>Sway</span>
        </div>
    </div>
);

const SwayDrawer: React.FC<IProps> = (props) => {
    const navigate = useNavigate();
    const location = useLocation();
    const ref = useRef<HTMLDivElement | null>(null);
    const [open, setOpen] = useOpenCloseElement(ref, !IS_MOBILE_PHONE);
    const [isLoaded, setLoaded] = useState<boolean>(false);

    const handleDrawerOpen = useCallback(() => setOpen(true), [setOpen]);

    const { user, menuChoices, bottomMenuChoices } = props;
    const pathname = location.pathname;

    useEffect(() => {
        if (!isLoaded && ref.current) {
            setLoaded(true);
        }
    }, [isLoaded]);

    const getMenuComponent = (
        text: string | React.ReactNode,
        Icon?: OverridableComponent<SvgIconTypeMap<Record<string, unknown>, "svg">>,
    ) => {
        logDev("SwayDrawer.getMenuComponent - Return title with text -", text);
        return (
            <>
                <Typography sx={{ pl: 2, pr: 1 }}>{text}</Typography>&nbsp;
                {Icon && <Icon />}
            </>
        );
    };

    const menuTitle = () => {
        if (!IS_MOBILE_PHONE) {
            logDev("SwayDrawer.menuTitle - NOT mobile phone. Return default menu title");
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
                logDev("SwayDrawer.menuTitle - NO menu choices. Return default menu title");
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
            signOut(auth)
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
            return <item.Icon user={user} withText={!IS_MOBILE_PHONE || open} />;
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
                    button
                    key={item.route + index}
                    selected={isSelected(item.route)}
                    onClick={() => getOnClick(item)}
                >
                    <ListItemIcon sx={{ pr: 1 }} style={{ minWidth: 0 }}>
                        {getIcon(item)}
                    </ListItemIcon>
                    {item.route ? (
                        <ListItemText>{item.text}</ListItemText>
                    ) : (
                        <ListItemText primary={item.text} />
                    )}
                    {isSelected(item.route) ? (
                        <ListItemIcon sx={{ minWidth: 0 }}>
                            <Circle className="fs-6" />
                        </ListItemIcon>
                    ) : null}
                </ListItem>
            );
        },
        [pathname],
    );

    logDev("IS_MOBILE_PHONE", IS_MOBILE_PHONE);

    logDev(
        "HEIGHT",
        ref.current?.offsetHeight,
        ref.current?.clientHeight,
        ref.current?.scrollHeight,
    );

    const container = window !== undefined ? () => window.document.body : undefined;

    const sx = !IS_MOBILE_PHONE
        ? { width: `calc(100% - ${DRAWER_WIDTH}px)`, ml: `${DRAWER_WIDTH}px` }
        : undefined;
    return (
        <div className="d-flex">
            <CssBaseline />
            <AppBar ref={ref} position="fixed" sx={sx}>
                <Toolbar className="pointer" onClick={handleDrawerOpen}>
                    {IS_MOBILE_PHONE && (
                        <IconButton
                            color="inherit"
                            aria-label="open drawer"
                            edge="start"
                            sx={{ mr: 2, display: { sm: "none" } }}
                        >
                            <SwaySvg src={"/menu.svg"} />
                        </IconButton>
                    )}
                    {menuTitle()}
                </Toolbar>
            </AppBar>
            <Box component="nav" sx={{ width: { sm: DRAWER_WIDTH } }} aria-label="mailbox folders">
                <Drawer
                    role="nav"
                    anchor="left"
                    open={open}
                    variant={IS_MOBILE_PHONE ? "temporary" : "permanent"}
                    container={container}
                    ModalProps={{
                        keepMounted: true, // Better open performance on mobile.
                    }}
                    sx={{
                        height: "100%",
                        width: DRAWER_WIDTH,
                        "& .MuiDrawer-paper": {
                            width: DRAWER_WIDTH,
                            boxSizing: "border-box",
                        },
                    }}
                >
                    <DefaultMenuTitle />
                    <List className="pt-2">{menuChoices.map(getListItem)}</List>
                    {!isEmptyObject(bottomMenuChoices) && (
                        <List>{bottomMenuChoices.map(getListItem)}</List>
                    )}
                    <SocialIconsList />
                </Drawer>
            </Box>
            <div className="container pb-5" style={{ marginTop: `${ref.current?.offsetHeight}px` }}>
                {props.children}
            </div>
        </div>
    );
};

export default SwayDrawer;
