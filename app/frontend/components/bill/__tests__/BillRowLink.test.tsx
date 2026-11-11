import { cleanup, render, screen } from "@testing-library/react";
import * as React from "react";
import { afterEach, describe, expect, it, vi } from "vitest";

vi.mock("@inertiajs/react", async (importActual) => ({
    ...(await importActual<typeof import("@inertiajs/react")>()),
    Link: ({
        href,
        className,
        children,
        prefetch,
        cacheFor,
        viewTransition,
        ...rest
    }: React.PropsWithChildren<{
        href: string;
        className?: string;
        prefetch?: string | boolean;
        cacheFor?: string | string[];
        viewTransition?: boolean;
    }>) => (
        <a
            href={href}
            className={className}
            data-prefetch={prefetch === undefined ? undefined : String(prefetch)}
            data-cache-for={Array.isArray(cacheFor) ? cacheFor.join(",") : cacheFor}
            data-view-transition={viewTransition ? "true" : undefined}
            {...(rest as object)}
        >
            {children}
        </a>
    ),
}));

import BillRowLink from "app/frontend/components/bill/BillRowLink";
import { PREFETCH_CACHE_FOR } from "app/frontend/sway_constants";

afterEach(() => {
    cleanup();
});

describe("BillRowLink", () => {
    it("resolves the bill path for a numeric id", () => {
        render(<BillRowLink billId={42}>Read bill</BillRowLink>);

        expect(screen.getByRole("link", { name: "Read bill" })).toHaveAttribute("href", "/bills/42");
    });

    it("resolves the bill path for a string id", () => {
        render(<BillRowLink billId="42">Read bill</BillRowLink>);

        expect(screen.getByRole("link", { name: "Read bill" })).toHaveAttribute("href", "/bills/42");
    });

    it("passes the caller's class name through unchanged", () => {
        render(
            <BillRowLink billId={1} className="cbl-item__title">
                Read bill
            </BillRowLink>,
        );

        expect(screen.getByRole("link", { name: "Read bill" })).toHaveClass("cbl-item__title");
    });

    it("renders its children unchanged", () => {
        render(
            <BillRowLink billId={1}>
                <span>Nested title</span>
            </BillRowLink>,
        );

        expect(screen.getByText("Nested title")).toBeInTheDocument();
    });

    it("warms the link on mousedown rather than on hover, and requests the crossfade", () => {
        render(<BillRowLink billId={1}>Read bill</BillRowLink>);

        const link = screen.getByRole("link", { name: "Read bill" });
        expect(link).toHaveAttribute("data-prefetch", "click");
        expect(link).toHaveAttribute("data-view-transition", "true");
    });

    it("states the shared prefetch cache window rather than inheriting the library default", () => {
        render(<BillRowLink billId={1}>Read bill</BillRowLink>);

        expect(screen.getByRole("link", { name: "Read bill" })).toHaveAttribute(
            "data-cache-for",
            PREFETCH_CACHE_FOR.join(","),
        );
    });
});
