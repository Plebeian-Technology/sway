import { afterEach, describe, expect, it } from "vitest";
import { cleanup, render, screen } from "@testing-library/react";

import SharedAddresses from "app/frontend/pages/admin/SharedAddresses";

const rows = [
    { address_ids: [7], user_count: 42 },
    { address_ids: [12], user_count: 3 },
    { address_ids: [3, 9], user_count: 2 },
];

afterEach(cleanup);

describe("admin/SharedAddresses", () => {
    it("renders a heading and one row per shared address with its id and user count", () => {
        render(<SharedAddresses shared_addresses={rows} />);

        expect(screen.getByRole("heading", { level: 1, name: "Shared Addresses" })).toBeInTheDocument();
        expect(screen.getByText("Address ID 7")).toBeInTheDocument();
        expect(screen.getByText("42 users")).toBeInTheDocument();
        expect(screen.getByText("Address ID 12")).toBeInTheDocument();
        expect(screen.getByText("3 users")).toBeInTheDocument();
        expect(screen.getByText("Address ID 3, 9")).toBeInTheDocument();
        expect(screen.getByText("2 users")).toBeInTheDocument();
        expect(screen.getByText("3 addresses")).toBeInTheDocument();
    });

    it("shows an empty message when no address is shared", () => {
        render(<SharedAddresses shared_addresses={[]} />);

        expect(screen.getByText("No address has been given by more than one registered user.")).toBeInTheDocument();
        expect(screen.getByText("0 addresses")).toBeInTheDocument();
    });

    it("pluralizes a single shared address and a single user", () => {
        render(<SharedAddresses shared_addresses={[{ address_ids: [1], user_count: 1 }]} />);

        expect(screen.getByText("1 address")).toBeInTheDocument();
        expect(screen.getByText("1 user")).toBeInTheDocument();
    });
});
