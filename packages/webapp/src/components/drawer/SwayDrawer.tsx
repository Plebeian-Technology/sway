/** @format */
import { Avatar, SvgIconTypeMap } from "@mui/material";
import { OverridableComponent } from "@mui/material/OverridableComponent";
import { ROUTES, SWAY_USER_REGISTERED } from "@sway/constants";
import { logDev, removeStorage } from "@sway/utils";
import { signOut } from "firebase/auth";
import React, { useCallback } from "react";
import { Dropdown } from "react-bootstrap";
import { FaBars, FaCircle } from "react-icons/fa";
import { useLocation, useNavigate } from "react-router-dom";
import { sway } from "sway";
import { auth } from "../../firebase";
import { handleError, IS_MOBILE_PHONE } from "../../utils";
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

const SwayDrawer: React.FC<IProps> = (props) => {
    const navigate = useNavigate();
    const location = useLocation();

    const { user, menuChoices, bottomMenuChoices } = props;
    const pathname = location.pathname;

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
            return <item.Icon user={user} className="opacity-75" />;
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
            if (item.route === "divider") {
                return <Dropdown.Divider key={item.route + index} />;
            }
            return (
                <Dropdown.Item
                    key={item.route + index}
                    selected={isSelected(item.route)}
                    onClick={() => getOnClick(item)}
                    className="row mx-0 py-3 fs-5 align-items-center"
                >
                    <span className="col-1 text-start px-0">{getIcon(item)}</span>
                    <span className="col-10">{item.text}</span>
                    <span className="col-1 text-end">
                        {isSelected(item.route) ? (
                            <FaCircle size={10} className="text-primary" />
                        ) : null}
                    </span>
                </Dropdown.Item>
            );
        },
        [pathname],
    );
    return (
        <>
            <div className="bg-primary d-flex flex-row align-items-center py-2">
                <Dropdown id="basic-navbar-nav">
                    <Dropdown.Toggle
                        id="dropdown-autoclose-true"
                        className="no-arrow-dropdown bg-transparent border-0 hide-focus-outline"
                    >
                        <FaBars />
                    </Dropdown.Toggle>
                    <Dropdown.Menu
                        id="basic-nav-dropdown"
                        className="ms-1"
                        style={{ width: DRAWER_WIDTH }}
                    >
                        {menuChoices.map(getListItem)}
                        <Dropdown.Divider />
                        {bottomMenuChoices.map(getListItem || [])}
                        <Dropdown.Divider className="my-3" />
                        <SocialIconsList />
                    </Dropdown.Menu>
                </Dropdown>
                <Avatar src={"/logo300.png"} />
                <span className="ms-2 text-white bold">Sway</span>
            </div>
            <div className="container pb-5">{props.children}</div>
        </>
    );
};

export default SwayDrawer;
