import SwayLoading from "app/frontend/components/SwayLoading";
import { PropsWithChildren, Suspense } from "react";

const SuspenseFullScreen: React.FC<PropsWithChildren> = ({ children }) => (
    <Suspense fallback={<SwayLoading />}>{children}</Suspense>
);

export default SuspenseFullScreen;
