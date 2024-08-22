import Footer from "app/frontend/components/Footer";
import AppDrawer from "app/frontend/components/drawer/AppDrawer";
import React, { PropsWithChildren } from "react";

// Load react-select
// @ts-expect-error - unused Select, importing here to have styles available
import { Animate } from "react-simple-animate";

interface IProps extends PropsWithChildren {
    [key: string]: any;
}

const _Layout: React.FC<IProps> = ({ children, ...props }) => (
    <AppDrawer>
        {React.Children.map(children, (child) => (
            <Animate play={true} start={{ opacity: 0 }} end={{ opacity: 1 }}>
                {React.isValidElement(child) ? React.cloneElement(child, { ...child?.props, ...props }) : child}
            </Animate>
        ))}

        <Footer />
    </AppDrawer>
);

// SetupPage sends locale + user to redux store
const Layout = _Layout;

const LayoutWithPage = (page: React.JSX.Element) => <Layout {...page.props}>{page}</Layout>;

export default LayoutWithPage;
