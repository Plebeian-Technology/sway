/** @format */
import { IS_MOBILE_PHONE, ROUTES } from "app/frontend/sway_constants";
import { logDev } from "app/frontend/sway_utils";
import { PropsWithChildren, useCallback, useRef, useState } from "react";
import { Container, Dropdown, Image, Nav, Navbar, Offcanvas, OverlayTrigger, Popover } from "react-bootstrap";
import { FiCircle, FiMenu } from "react-icons/fi";
import { sway } from "sway";
import { useLogout } from "../../hooks/users/useLogout";

import { router } from "@inertiajs/react";
import SwayLoading from "app/frontend/components/SwayLoading";
import { useOpenCloseElement } from "app/frontend/hooks/elements/useOpenCloseElement";
import { useUser } from "app/frontend/hooks/users/useUser";
import { formatPhone } from "app/frontend/sway_utils/phone";
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

const Brand = () => {
    const user = useUser();

    return (
        <OverlayTrigger
            key="overlay"
            placement={"bottom"}
            overlay={
                user?.phone ? (
                    <Popover id="sway-drawer-popover">
                        <Popover.Header as="h3">Logged in as:</Popover.Header>
                        <Popover.Body>
                            <div className="col">
                                <div className="px-0">{formatPhone(user.phone)}</div>
                            </div>
                        </Popover.Body>
                    </Popover>
                ) : (
                    <></>
                )
            }
        >
            <span style={{ zIndex: 1000 }}>
                <Image src={"/images/logo300.png"} style={{ maxWidth: 30 }} className="d-inline-block align-top" />
                <span className="ms-2">Sway</span>
            </span>
        </OverlayTrigger>
    );
};

const SwayDrawer: React.FC<IProps> = (props) => {
    const logout = useLogout();
    const ref = useRef(null);
    const [isExpanded, setExpanded] = useOpenCloseElement(ref, false);
    const [isLoading, setLoading] = useState<boolean>(false);
    const { menuChoices, bottomMenuChoices } = props;

    const onFinish = useCallback(() => {
        setLoading(false);
        setExpanded(false);
    }, [setExpanded]);

    const handleNavigate = useCallback(
        (route: string, state?: Record<string, any>) => {
            logDev("Navigating to route -", route);
            setLoading(true);

            if (route === ROUTES.signin) {
                router.visit("/", {
                    replace: true,
                    onFinish,
                });
            } else if (state) {
                router.visit(route, {
                    data: state,
                    onFinish,
                });
            } else {
                router.visit(route, {
                    onFinish,
                });
            }
        },
        [onFinish],
    );

    const getOnClick = useCallback(
        (item: MenuItem) => {
            if (item.route === ROUTES.invite) {
                setExpanded(false);
                return;
            }

            if (item.route === ROUTES.logout) {
                logout();
                setExpanded(false);
            } else {
                handleNavigate(item.route, { title: item.text });
            }
        },
        [handleNavigate, logout, setExpanded],
    );

    const getIcon = useCallback((item: MenuItem) => {
        if (item.route === ROUTES.invite) {
            return <item.Icon withText={!IS_MOBILE_PHONE} />;
        } else {
            return <item.Icon className="opacity-75" />;
        }
    }, []);

    const getListItem = useCallback(
        (item: MenuItem, index: number) => {
            const isSelected = item.route === window.location.pathname;

            if (item.route === ROUTES.invite) {
                return <item.Icon key={item.route + index} withText={!IS_MOBILE_PHONE} />;
            }
            if (item.route === "divider") {
                return <Dropdown.Divider key={item.route + index} />;
            }
            return (
                <Nav.Link
                    key={item.route + index}
                    disabled={isLoading}
                    onClick={(e) => {
                        e.preventDefault();
                        e.stopPropagation();

                        getOnClick(item);
                    }}
                    href={item.route}
                    className="row mx-0 py-3 fs-5 align-items-center"
                >
                    <span className="col-1 text-start px-0">{getIcon(item)}</span>
                    <span className="col-10">{item.text}</span>
                    <span className="col-1 text-end">
                        {isSelected ? <FiCircle size={10} fill={SWAY_COLORS.primary} className="text-primary" /> : null}
                    </span>
                </Nav.Link>
            );
        },
        [getIcon, getOnClick, isLoading],
    );

    return (
        <>
            <Navbar ref={ref} bg="light" expand={false} sticky="top" expanded={isExpanded}>
                <Container fluid>
                    <Navbar.Offcanvas
                        id={`offcanvasNavbar-expand`}
                        aria-labelledby={`offcanvasNavbarLabel-true`}
                        placement="start"
                    >
                        <Offcanvas.Header closeButton onClick={() => setExpanded(false)}>
                            <Offcanvas.Title id={`offcanvasNavbarLabel-expand`}>
                                <Brand />
                            </Offcanvas.Title>
                            <div style={{ maxWidth: 35, margin: "0px auto" }}>
                                <SwayLoading isHidden={!isLoading} />
                            </div>
                        </Offcanvas.Header>
                        <Offcanvas.Body>
                            <Nav className="justify-content-end flex-grow-1 pe-3">
                                {/* <ProgressBar animated striped now={100} style={{ height: 2 }} /> */}
                                {menuChoices.map(getListItem)}
                                {bottomMenuChoices.map(getListItem || [])}
                                <SocialIconsList />
                            </Nav>
                        </Offcanvas.Body>
                    </Navbar.Offcanvas>

                    <Navbar.Toggle
                        aria-controls={`offcanvasNavbar-expand`}
                        className="border-0"
                        onClick={() => setExpanded(true)}
                    >
                        <FiMenu />
                    </Navbar.Toggle>

                    <Navbar.Brand>
                        <Brand />
                    </Navbar.Brand>
                </Container>
            </Navbar>

            <div className={`${IS_MOBILE_PHONE ? "container-fluid" : "container"} pb-5 h-100 main`}>
                <div className={"col-12 mx-auto"}>{props.children}</div>
            </div>
        </>
    );
};

export default SwayDrawer;
