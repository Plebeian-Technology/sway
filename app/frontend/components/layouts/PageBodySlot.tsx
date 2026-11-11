import { PropsWithChildren, useEffect, useRef } from "react";

import { useNavigationState } from "app/frontend/navigation/navigationStore";
import { SHAPE_COMPONENTS } from "app/frontend/navigation/shapes";

// @lat: [[system-shape#What a reader sees during the round trip#Why the outgoing page is not painted under the placeholder]]
// @lat: [[system-shape#What a reader sees during the round trip#Why focus moves to the slot's status region]]

type IProps = PropsWithChildren;

const PageBodySlot: React.FC<IProps> = ({ children }) => {
    const { placeholder, pageName, dim } = useNavigationState();
    const Shape = placeholder ? SHAPE_COMPONENTS[placeholder] : null;
    const busy = Boolean(placeholder) || dim;
    const outgoingTreatment = Shape ? "nav-replaced " : dim ? "nav-leaving " : "";
    const outgoingRef = useRef<HTMLDivElement>(null);
    const statusRef = useRef<HTMLOutputElement>(null);
    const lastFocusedRef = useRef<Element | null>(null);

    useEffect(() => {
        const remember = (event: FocusEvent): void => {
            lastFocusedRef.current = event.target as Element;
        };
        document.addEventListener("focusin", remember);
        return () => document.removeEventListener("focusin", remember);
    }, []);

    useEffect(() => {
        const status = statusRef.current;
        const outgoing = outgoingRef.current;

        if (!dim) {
            if (status && document.activeElement === status) {
                outgoing?.focus({ preventScroll: true });
            }
            return;
        }

        const last = lastFocusedRef.current;
        const active = document.activeElement;
        const readerWasInside = Boolean(last) && last !== outgoing && Boolean(outgoing?.contains(last));
        // @lat: [[system-shape#What a reader sees during the round trip#Why focus moves to the slot's status region]]
        if (!outgoing || (!readerWasInside && active !== outgoing)) return;

        if (!active || active === document.body || outgoing.contains(active)) {
            status?.focus({ preventScroll: true });
        }
    }, [dim]);

    return (
        <div className="grid grid-cols-1" aria-busy={busy || undefined} data-testid="page-body-slot">
            <output ref={statusRef} tabIndex={-1} aria-live="polite" aria-atomic="true" className="sr-only">
                {busy ? `Loading ${pageName ?? "page"}` : ""}
            </output>
            <div
                ref={outgoingRef}
                className={`${outgoingTreatment}col-start-1 row-start-1 min-w-0`}
                inert={dim}
                tabIndex={-1}
                data-testid="page-body-outgoing"
            >
                {children}
            </div>
            {Shape && (
                <div className="col-start-1 row-start-1 min-w-0" data-testid="page-body-placeholder">
                    <Shape />
                </div>
            )}
        </div>
    );
};

export default PageBodySlot;
