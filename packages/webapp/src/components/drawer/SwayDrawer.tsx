/** @format */
import { ROUTES } from "@sway/constants";
import { logDev } from "@sway/utils";
import React, { useCallback } from "react";
import { Button, Container, Dropdown, Image, Nav, Navbar, NavDropdown } from "react-bootstrap";
import { FiArrowLeft, FiCircle, FiMenu } from "react-icons/fi";
import { useLocation, useNavigate } from "react-router-dom";
import { sway } from "sway";
import { useLogout } from "../../hooks";
import { IS_MOBILE_PHONE, IS_TAURI, SWAY_COLORS } from "../../utils";
import SocialIconsList from "../user/SocialIconsList";

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
                <NavDropdown.Item
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
                </NavDropdown.Item>
            );
        },
        [pathname],
    );

    const handleBack = useCallback(() => navigate(-1), []);

    return (
        <>
            <Navbar bg="light" expand={true}>
                <Container>
                    <Navbar.Toggle aria-controls="basic-navbar-nav" />
                    <Navbar.Collapse id="basic-navbar-nav">
                        {IS_TAURI && !!window.history.state.idx && (
                            <Button
                                onClick={handleBack}
                                variant="outline-primary"
                                className="border-0"
                                size="sm"
                            >
                                <FiArrowLeft />
                            </Button>
                        )}
                        <Nav>
                            <NavDropdown
                                id="basic-nav-dropdown"
                                title={<FiMenu className="text-primary" />}
                            >
                                {menuChoices.map(getListItem)}
                                <Dropdown.Divider />
                                {bottomMenuChoices.map(getListItem || [])}
                                <Dropdown.Divider className="my-3" />
                                <SocialIconsList />
                            </NavDropdown>
                        </Nav>
                    </Navbar.Collapse>
                    <Navbar.Brand className="w-100 text-end">
                        <Image
                            src={"/logo300.png"}
                            style={{ maxWidth: 30 }}
                            className="d-inline-block align-top"
                        />
                        <span className="ms-2">Sway</span>
                    </Navbar.Brand>
                </Container>
            </Navbar>

            <div className="container pb-5 vh-100">
                {!IS_MOBILE_PHONE && <div className="col-2">&nbsp;</div>}
                {!IS_MOBILE_PHONE ? (
                    <div className="col-8 mx-auto">{props.children}</div>
                ) : (
                    props.children
                )}
                {!IS_MOBILE_PHONE && <div className="col-2">&nbsp;</div>}
            </div>
        </>
    );
};

export default SwayDrawer;
