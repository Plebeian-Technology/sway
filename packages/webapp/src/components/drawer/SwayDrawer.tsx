/** @format */
import { ROUTES } from "@sway/constants";
import { logDev } from "@sway/utils";
import React, { useCallback } from "react";
import { Dropdown, Image } from "react-bootstrap";
import { FiCircle, FiMenu } from "react-icons/fi";
import { useLocation, useNavigate } from "react-router-dom";
import { sway } from "sway";
import { useLogout } from "../../hooks";
import { IS_MOBILE_PHONE, SWAY_COLORS } from "../../utils";
import SocialIconsList from "../user/SocialIconsList";

const DRAWER_WIDTH = 300;

type MenuItem = {
    route: string;
    Icon: React.FC<any>;
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
    const logout = useLogout();

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
            logout();
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
                            <FiCircle
                                size={10}
                                fill={SWAY_COLORS.primary}
                                className="text-primary"
                            />
                        ) : null}
                    </span>
                </Dropdown.Item>
            );
        },
        [pathname],
    );

    const handleBack = useCallback(() => navigate(-1), []);

    return (
        <>
            <div className="bg-primary row align-items-center py-2 sticky-top">
                <div className="col-4">
                    <div className="row align-items-center">
                        <Dropdown id="basic-navbar-nav" className="col-3 col-sm-2">
                            <Dropdown.Toggle
                                id="dropdown-autoclose-true"
                                className="no-arrow-dropdown bg-transparent border-0 hide-focus-outline py-0"
                            >
                                <FiMenu />
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
                        <div className="col-5 col-sm-2">
                            <Image
                                roundedCircle
                                thumbnail
                                className="border-0"
                                src={"/logo300.png"}
                                style={{ maxWidth: 50 }}
                            />
                        </div>
                        <div className="col-3 col-sm-2 text-start">
                            <span className="text-white bold align-text-top">Sway</span>
                        </div>
                    </div>
                </div>
                {window.history.state.idx > 0 && (
                    <div className="col-7 text-end pr-0">
                        <span
                            onClick={handleBack}
                            className="text-white bold align-text-top pointer"
                        >
                            Back
                        </span>
                    </div>
                )}
            </div>
            <div className="container pb-5">{props.children}</div>
        </>
    );
};

export default SwayDrawer;
