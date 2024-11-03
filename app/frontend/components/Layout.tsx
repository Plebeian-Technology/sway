import Footer from "app/frontend/components/Footer";
import AppDrawer from "app/frontend/components/drawer/AppDrawer";
import React, { Fragment, PropsWithChildren } from "react";
import { Fade } from "react-bootstrap";

interface IProps extends PropsWithChildren {
    [key: string]: any;
}

const _Layout: React.FC<IProps> = ({ children, ...props }) => (
    <AppDrawer>
        {React.Children.map(children, (child, i) => (
            <Fade in={true}>
                {React.isValidElement(child) ? (
                    React.cloneElement(child, { ...child?.props, ...props })
                ) : (
                    <Fragment key={`layout-child-${i}`}></Fragment>
                )}
            </Fade>
        ))}

        <Footer />
    </AppDrawer>
);

// SetupPage sends locale + user to redux store
const Layout = _Layout;

const LayoutWithPage = (page: React.JSX.Element) => <Layout {...page.props}>{page}</Layout>;

export default LayoutWithPage;
