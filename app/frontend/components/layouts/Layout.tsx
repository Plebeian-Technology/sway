import Footer from "app/frontend/components/Footer";
import AppDrawer from "app/frontend/components/drawer/AppDrawer";
import { logDev, notify } from "app/frontend/sway_utils";
import React, { Fragment, PropsWithChildren, useEffect } from "react";

interface IProps extends PropsWithChildren {
    withFade?: boolean;
    withFlash?: boolean;
    [key: string]: any;
}

const Layout: React.FC<IProps> = ({ children, withFade = true, withFlash = true, ...props }) => {
    logDev("Layout.props.flash", props.flash);
    useEffect(() => {
        if (!withFlash) return;

        if (props.flash?.notice) {
            notify({
                level: "success",
                title: props.flash.notice,
                position: "top-center",
                duration: 5000,
            });
        }
        if (props.flash?.alert) {
            notify({
                level: "error",
                title: props.flash.alert,
                position: "top-center",
                duration: 5000,
            });
        }
    }, [props.flash?.notice, props.flash?.alert, withFlash]);

    return (
        <AppDrawer>
            {React.Children.map(children, (child, i) => (
                <div className={withFade ? "fade-in-and-up" : undefined}>
                    <div>
                        {React.isValidElement(child) ? (
                            React.cloneElement(child, { ...(child.props as Record<string, any>), ...props })
                        ) : (
                            <Fragment key={`layout-child-${i}`}></Fragment>
                        )}
                    </div>
                </div>
            ))}

            <Footer />
        </AppDrawer>
    );
};

const LayoutWithPage = (page: React.JSX.Element) => <Layout {...page.props}>{page}</Layout>;

export default LayoutWithPage;
