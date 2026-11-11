import { describe, expect, it } from "vitest";
import { FieldShell } from "app/frontend/components/admin/creator/fields/FieldShell";
import { renderV2 } from "app/frontend/__tests__/test-utils";

const childInput = <input id="test-field" aria-label="test field" />;

describe("FieldShell", () => {
    it("renders the label with a required asterisk when required=true", () => {
        const { getByText } = renderV2(
            <FieldShell name="test-field" label="Title" required>
                {childInput}
            </FieldShell>,
        );

        expect(getByText("Title")).toBeInTheDocument();
        expect(getByText("*", { exact: false })).toBeInTheDocument();
    });

    it("renders the label with '(Optional)' when required is false or missing", () => {
        const { getByText } = renderV2(
            <FieldShell name="test-field" label="Notes">
                {childInput}
            </FieldShell>,
        );

        expect(getByText("(Optional)", { exact: false })).toBeInTheDocument();
    });

    it("wires the label htmlFor to the child input's id via `name`", () => {
        const { getByText } = renderV2(
            <FieldShell name="test-field" label="Title">
                {childInput}
            </FieldShell>,
        );

        expect(getByText("Title").closest("label")).toHaveAttribute("for", "test-field");
    });

    it("renders helperText below the input when present", () => {
        const { getByText } = renderV2(
            <FieldShell name="test-field" label="Title" helperText="Up to 120 characters">
                {childInput}
            </FieldShell>,
        );

        expect(getByText("Up to 120 characters")).toBeInTheDocument();
    });

    it("renders the error with role='alert' and hides it when absent", () => {
        const { queryByRole, rerender } = renderV2(
            <FieldShell name="test-field" label="Title">
                {childInput}
            </FieldShell>,
        );

        expect(queryByRole("alert")).toBeNull();

        rerender(
            <div data-theme="v2">
                <FieldShell name="test-field" label="Title" error="Required">
                    {childInput}
                </FieldShell>
            </div>,
        );

        const alert = queryByRole("alert");
        expect(alert).not.toBeNull();
        expect(alert).toHaveTextContent("Required");
    });

    it("omits the label entirely when no label prop is provided", () => {
        const { container } = renderV2(
            <FieldShell name="test-field">
                <input data-testid="bare" />
            </FieldShell>,
        );

        expect(container.querySelector("label")).toBeNull();
    });

    it("passes className through to the outer wrapper", () => {
        const { container } = renderV2(
            <FieldShell name="test-field" label="Title" className="custom-class">
                {childInput}
            </FieldShell>,
        );

        const outer = container.querySelector(".custom-class");
        expect(outer).not.toBeNull();
    });
});
