// @lat: [[error-boundary-hierarchy#Page-level: PageErrorBoundary]]

import * as React from "react";
import { usePage } from "@inertiajs/react";
import { Button } from "app/frontend/components/ui/button";
import { onRenderError } from "app/frontend/components/error_handling/utils";

const PageErrorFallback = ({ onRetry }: { onRetry: () => void }) => (
    <div role="alert" className="mx-auto flex max-w-md flex-col items-center gap-3 py-16 text-center">
        <p className="text-lg font-black text-foreground">This page hit an error.</p>
        <p className="text-sm text-muted-foreground">
            The rest of Sway is still working — try again, or navigate elsewhere.
        </p>
        <Button variant="outline" onClick={onRetry}>
            Try again
        </Button>
    </div>
);

class Boundary extends React.Component<
    { children: React.ReactNode; resetKey: string },
    { hasError: boolean; prevResetKey: string }
> {
    state = { hasError: false, prevResetKey: "" };

    static getDerivedStateFromError() {
        return { hasError: true };
    }

    static getDerivedStateFromProps(props: { resetKey: string }, state: { hasError: boolean; prevResetKey: string }) {
        // @lat: [[error-boundary-hierarchy#Why PageErrorBoundary uses a resetKey prop instead of a React key]]
        if (state.hasError && props.resetKey !== state.prevResetKey) {
            return { hasError: false, prevResetKey: props.resetKey };
        }
        if (props.resetKey !== state.prevResetKey) {
            return { prevResetKey: props.resetKey };
        }
        return null;
    }

    componentDidCatch(error: Error) {
        onRenderError(error);
    }

    reset = () => this.setState({ hasError: false });

    render() {
        return this.state.hasError ? <PageErrorFallback onRetry={this.reset} /> : this.props.children;
    }
}

interface IProps {
    children: React.ReactNode;
}

const PageErrorBoundary: React.FC<IProps> = ({ children }) => {
    const { url } = usePage();
    return <Boundary resetKey={url}>{children}</Boundary>;
};

export default PageErrorBoundary;
