import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import Profile from "../Profile";

describe("Profile", () => {
    it("renders user information and address", () => {
        const user = {
            email: "test@example.com",
            full_name: "Test User",
            created_at: "2026-01-01T00:00:00Z"
        };
        const address = {
            full_address: "123 Main St, Anytown, MD 12345"
        };
        render(<Profile user={user} address={address} />);
        expect(screen.getByText("test@example.com")).toBeDefined();
        expect(screen.getByText("Test User")).toBeDefined();
        expect(screen.getByText("123 Main St, Anytown, MD 12345")).toBeDefined();
    });
});
