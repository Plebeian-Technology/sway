import FullScreenLoading from "app/frontend/components/dialogs/FullScreenLoading";
import { PropsWithChildren, Suspense } from "react";

const SuspenseFullScreen: React.FC<PropsWithChildren> = ({ children }) => (
    <Suspense fallback={<FullScreenLoading />}>{children}</Suspense>
);

export default SuspenseFullScreen;
