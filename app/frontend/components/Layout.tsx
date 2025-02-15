import Footer from "app/frontend/components/Footer";
import AppDrawer from "app/frontend/components/drawer/AppDrawer";
import React, { Fragment, PropsWithChildren } from "react";

interface IProps extends PropsWithChildren {
    [key: string]: any;
}

const Layout_: React.FC<IProps> = ({ children, ...props }) => (
    <AppDrawer>
        {React.Children.map(children, (child, i) => (
            <div className="fade-in-and-up">
                {/* <Fade in={true}> */}
                <div>
                    {React.isValidElement(child) ? (
                        React.cloneElement(child, { ...(child.props as Record<string, any>), ...props })
                    ) : (
                        <Fragment key={`layout-child-${i}`}></Fragment>
                    )}
                </div>
                {/* </Fade> */}
            </div>
        ))}

        <Footer />
    </AppDrawer>
);

// SetupPage sends locale + user to redux store
const Layout = Layout_;

const LayoutWithPage = (page: React.JSX.Element) => <Layout {...page.props}>{page}</Layout>;

export default LayoutWithPage;
