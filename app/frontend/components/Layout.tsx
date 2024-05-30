import Footer from "app/frontend/components/Footer";
import AppDrawer from "app/frontend/components/drawer/AppDrawer";
import SetupPage from "app/frontend/components/hoc/SetupPage";
import React, { PropsWithChildren } from "react";

// Load react-select
// @ts-ignore
import Select from "react-select"; // eslint-disable-line

interface IProps extends PropsWithChildren {
    [key: string]: any;
}

const _Layout: React.FC<IProps> = ({ children, ...props }) => (
    <AppDrawer>
        {React.Children.map(children, (child) =>
            React.isValidElement(child) ? React.cloneElement(child, { ...child?.props, ...props }) : child,
        )}

        <Footer />

        {/* <div className="min-h-full">
            <nav className="bg-white shadow-sm">
                <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
                    <div className="flex justify-between h-16">
                        <div className="flex">
                            <div className="hidden sm:-my-px sm:ml-6 sm:flex sm:space-x-8">
                                <InertiaLink
                                    href="/"
                                    className="border-transparent text-gray-900 inline-flex items-center px-1 pt-1 border-b-2 text-sm font-medium"
                                    aria-current="page"
                                >
                                    Home
                                </InertiaLink>
                            </div>
                        </div>
                    </div>
                </div>
            </nav>

            <div className="py-10">
                <main>
                    <div className="max-w-7xl mx-auto sm:px-6 lg:px-8">
                        <div className="px-4 py-8 sm:px-0">
                            <div className="bg-white rounded-lg h-96 p-3">
                                {children}
                            </div>
                        </div>
                    </div>
                </main>
            </div>
        </div> */}
    </AppDrawer>
);

// SetupPage sends locale + user to redux store
const Layout = SetupPage(_Layout)

const LayoutWithPage = (page: React.JSX.Element) => <Layout {...page.props}>{page}</Layout>;

export default LayoutWithPage;
