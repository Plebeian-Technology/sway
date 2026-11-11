import { PropsWithChildren } from "react";

import AppVersionFooter from "app/frontend/components/brand/AppVersionFooter";
import BrandMark from "app/frontend/components/brand/BrandMark";
import ReleaseInfo from "app/frontend/components/brand/ReleaseInfo";
import PageErrorBoundary from "app/frontend/components/error_handling/PageErrorBoundary";
import PageBodySlot from "app/frontend/components/layouts/PageBodySlot";

type IProps = PropsWithChildren;

const NoAuthLayout: React.FC<IProps> = ({ children }) => {
    return (
        <div className="flex min-h-svh flex-col bg-background text-foreground">
            <header className="border-b-neo border-border-soft bg-card/90 backdrop-blur">
                <div className="mx-auto flex w-full max-w-5xl items-center justify-between gap-3 px-4 py-3.5 sm:px-6 lg:px-8">
                    <ReleaseInfo>
                        <div className="flex items-center gap-3">
                            <BrandMark className="size-10 rounded-lg shadow-neo" />
                            <div className="flex flex-col">
                                <span className="text-xl font-black leading-none tracking-tight text-foreground">
                                    Sway
                                </span>
                                <span className="mt-0.5 text-xs font-medium text-muted-foreground">
                                    Civic accountability
                                </span>
                            </div>
                        </div>
                    </ReleaseInfo>
                </div>
            </header>

            <main className="mx-auto flex w-full max-w-5xl flex-1 flex-col justify-start px-4 py-6 sm:px-6 sm:py-10 lg:justify-center lg:px-8 lg:py-12">
                <section className="min-w-0">
                    <PageBodySlot>
                        <PageErrorBoundary>{children}</PageErrorBoundary>
                    </PageBodySlot>
                </section>
            </main>

            <div className="mx-auto w-full max-w-5xl px-4 pb-6 sm:px-6 lg:px-8">
                <AppVersionFooter />
            </div>
        </div>
    );
};

const NoAuthPageLayout = (page: React.JSX.Element) => <NoAuthLayout {...page.props}>{page}</NoAuthLayout>;

export default NoAuthPageLayout;
