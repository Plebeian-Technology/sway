/** @format */
import { IS_MOBILE_PHONE, ROUTES } from "app/frontend/sway_constants";
import { logDev } from "app/frontend/sway_utils";
import { PropsWithChildren, useCallback } from "react";
import {
    Container,
    Dropdown,
    Image,
    Nav,
    NavDropdown,
    Navbar,
    OverlayTrigger,
    Popover
} from "react-bootstrap";
import { FiCircle, FiMenu } from "react-icons/fi";
import { sway } from "sway";
import { useLogout } from "../../hooks/users/useLogout";

import { router } from "@inertiajs/react";
import { SWAY_COLORS } from "../../sway_utils";
import SocialIconsList from "../user/SocialIconsList";

type MenuItem = {
    route: string;
    Icon: React.FC<any>;
    text: string | React.ReactNode;
};

interface IProps extends PropsWithChildren {
    menuChoices: MenuItem[];
    bottomMenuChoices: MenuItem[];
    user?: sway.IUser;
}

const SwayDrawer: React.FC<IProps> = (props) => {
    const logout = useLogout();

    const isBotwCreator = window.location.pathname === ROUTES.billOfTheWeekCreator

    const { user, menuChoices, bottomMenuChoices } = props;

    const handleNavigate = useCallback(
        (route: string, state?: Record<string, any>) => {
            logDev("Navigating to route -", route);

            if (route === ROUTES.signin) {
                router.visit("/", { replace: true });
            } else if (state) {
                router.visit(route, state);
            } else {
                router.visit(route);
            }
        },
        [],
    );

    const isSelected = (route: string) => route === window.location.pathname

    const getOnClick = useCallback(
        (item: MenuItem) => {
            if (item.route === "invite") return;

            if (item.route === ROUTES.logout) {
                logout();
            } else {
                handleNavigate(item.route, { title: item.text });
            }
        },
        [handleNavigate, logout],
    );

    const getIcon = useCallback((item: MenuItem) => {
        if (item.route === "invite") {
            return <item.Icon withText={!IS_MOBILE_PHONE} />;
        } else {
            return <item.Icon className="opacity-75" />;
        }
    }, []);

    const getListItem = useCallback(
        (item: MenuItem, index: number) => {
            if (item.route === "invite") {
                return <item.Icon key={item.route + index} withText={!IS_MOBILE_PHONE} />;
            }
            if (item.route === "divider") {
                return <Dropdown.Divider key={item.route + index} />;
            }
            return (
                <NavDropdown.Item
                    key={item.route + index}
                    // selected={isSelected(item.route)}
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
        [getOnClick, getIcon, isSelected],
    );

    return (
        <>
            <Navbar bg="light" expand={true} className="py-0">
                <Container>
                    <Navbar.Toggle aria-controls="basic-navbar-nav" />
                    <Navbar.Collapse
                        id="basic-navbar-nav"
                        className="h-100 py-2"
                        style={{ zIndex: 1000 }}
                    >
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
                        <OverlayTrigger
                            key="overlay"
                            placement={"bottom"}
                            overlay={
                                <Popover id="sway-drawer-popover">
                                    <Popover.Header as="h3">Logged in as:</Popover.Header>
                                    <Popover.Body>
                                        <div className="col">
                                            <div className="px-0">{user?.phone}</div>
                                            {/* <div className="px-0">{user?.email}</div> */}
                                        </div>
                                    </Popover.Body>
                                </Popover>
                            }
                        >
                            <span style={{ zIndex: 1000 }}>
                                <Image
                                    src={"/assets/logo300.png"}
                                    style={{ maxWidth: 30 }}
                                    className="d-inline-block align-top"
                                />
                                <span className="ms-2">Sway</span>
                            </span>
                        </OverlayTrigger>
                    </Navbar.Brand>
                </Container>
            </Navbar>

            <div className={`${IS_MOBILE_PHONE ? "container-fluid" : "container"} pb-5 h-100`}>
                {isBotwCreator ? null : <div className="col-0 col-lg-2">&nbsp;</div>}
                <div className={`col-12 col-lg-${isBotwCreator ? "12" : "8"} mx-auto`}>
                    {props.children}
                </div>
                {isBotwCreator ? null : <div className="col-0 col-lg-2">&nbsp;</div>}
            </div>
        </>
    );
};

export default SwayDrawer;
