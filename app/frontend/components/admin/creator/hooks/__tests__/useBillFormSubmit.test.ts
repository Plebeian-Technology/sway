// @lat: [[identity-and-access#Identity and access#Sessions, cookies and bearer tokens#A refused CSRF write leaves a fresh retry path]]

import { act, renderHook } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

const formPost = vi.fn<(...args: unknown[]) => void>();
const formPut = vi.fn<(...args: unknown[]) => void>();
const notify = vi.fn<(options: Record<string, unknown>) => void>();

vi.mock("app/frontend/sway_utils", () => ({
    notify: (options: Record<string, unknown>) => notify(options),
}));

import { useBillFormSubmit } from "../useBillFormSubmit";
import type { InertiaFormProps } from "@inertiajs/react";
import type { IApiBillCreator } from "app/frontend/components/admin/creator/types";

beforeEach(() => {
    formPost.mockReset();
    formPut.mockReset();
    notify.mockReset();
});

describe("useBillFormSubmit — a refused save must not look like a saved one", () => {
    const onSaved = vi.fn<() => void>();

    const submitOptions = (): { onSuccess?: (page: { url: string; props: Record<string, unknown> }) => void } => {
        onSaved.mockReset();

        const form = {
            data: {
                id: 42,
                status: "introduced",
                chamber: "house",
                legislator_id: 1,
            },
            setData: vi.fn<(key: string, value: unknown) => void>(),
            transform: vi.fn<(callback: (data: unknown) => unknown) => void>(),
            post: formPost,
            put: formPut,
        } as unknown as InertiaFormProps<IApiBillCreator>;

        const initialValues = {
            id: 42,
            status: "introduced",
            chamber: "house",
            legislator_id: 1,
        } as unknown as IApiBillCreator;

        const { result } = renderHook(() =>
            useBillFormSubmit({
                form,
                initialValues,
                swayLocaleId: 7,
                onSaved,
            }),
        );

        const formElement = document.createElement("form");
        [
            ["status", "introduced"],
            ["chamber", "council"],
            ["legislator_id", "1"],
        ].forEach(([name, value]) => {
            const input = document.createElement("input");
            input.name = name;
            input.value = value;
            formElement.appendChild(input);
        });

        const event = {
            preventDefault: vi.fn<() => void>(),
            currentTarget: formElement,
        } as unknown as React.SubmitEvent<HTMLFormElement>;

        act(() => result.current.onSubmit(event));

        expect(formPut).toHaveBeenCalledTimes(1);
        return formPut.mock.calls[0][1] as {
            onSuccess?: (page: { url: string; props: Record<string, unknown> }) => void;
        };
    };

    it("does not clear the dirty flag when the page expired", () => {
        submitOptions().onSuccess?.({
            url: "/bills/42",
            props: { flash: { page_expired: true } },
        });

        expect(onSaved).not.toHaveBeenCalled();
    });

    it("tells the operator nothing was saved when the page expired", () => {
        submitOptions().onSuccess?.({
            url: "/bills/42",
            props: { flash: { page_expired: true } },
        });

        expect(notify).toHaveBeenCalledWith({
            level: "error",
            title: expect.stringMatching(/nothing was saved/i),
        });
    });

    it("clears the dirty flag on an ordinary landed save", () => {
        submitOptions().onSuccess?.({
            url: "/bills/42",
            props: { flash: {} },
        });

        expect(onSaved).toHaveBeenCalledTimes(1);
        expect(notify).not.toHaveBeenCalled();
    });

    it("includes news_usage: 'none' in the transformed submission payload", () => {
        const form = {
            data: {
                id: 42,
                status: "introduced",
                chamber: "house",
                legislator_id: 1,
            },
            setData: vi.fn<(key: string, value: unknown) => void>(),
            transform: vi.fn<(callback: (data: Record<string, unknown>) => Record<string, unknown>) => void>(),
            post: formPost,
            put: formPut,
        } as unknown as InertiaFormProps<IApiBillCreator>;

        const initialValues = {
            id: 42,
            status: "introduced",
            chamber: "house",
            legislator_id: 1,
        } as unknown as IApiBillCreator;

        const { result } = renderHook(() =>
            useBillFormSubmit({
                form,
                initialValues,
                swayLocaleId: 7,
                onSaved,
            }),
        );

        const formElement = document.createElement("form");
        [
            ["status", "introduced"],
            ["chamber", "council"],
            ["legislator_id", "1"],
        ].forEach(([name, value]) => {
            const input = document.createElement("input");
            input.name = name;
            input.value = value;
            formElement.appendChild(input);
        });

        const event = {
            preventDefault: vi.fn<() => void>(),
            currentTarget: formElement,
        } as unknown as React.SubmitEvent<HTMLFormElement>;

        act(() => result.current.onSubmit(event));

        expect(form.transform).toHaveBeenCalledTimes(1);
        const transformFn = vi.mocked(form.transform).mock.calls[0][0];
        const transformed = transformFn({} as unknown as IApiBillCreator) as IApiBillCreator;
        expect(transformed.news_usage).toBe("none");
    });

    it("submits externally updated summary data when the disabled textarea is absent from FormData", () => {
        const formData = {
            summary: "The initial form summary",
            status: "introduced",
            chamber: "house",
            legislator_id: 1,
        } as unknown as IApiBillCreator;
        let transformPayload: ((data: IApiBillCreator) => IApiBillCreator) | undefined;
        const formState = {
            data: formData,
            setData: vi.fn<(key: string, value: unknown) => void>(),
            transform: vi.fn<(callback: (data: IApiBillCreator) => IApiBillCreator) => void>((callback) => {
                transformPayload = callback;
            }),
            post: formPost,
            put: formPut,
        };
        formState.setData = vi.fn<(key: string, value: unknown) => void>((key, value) => {
            formState.data = { ...formState.data, [key]: value };
        });
        const form = formState as unknown as InertiaFormProps<IApiBillCreator>;
        const initialValues = { ...formData, id: 42 };

        const { result, rerender } = renderHook(() =>
            useBillFormSubmit({
                form,
                initialValues,
                swayLocaleId: 7,
                onSaved,
            }),
        );

        const formElement = document.createElement("form");
        const summary = document.createElement("textarea");
        summary.name = "summary";
        summary.value = formData.summary ?? "";
        summary.disabled = true;
        formElement.appendChild(summary);
        [
            ["status", "introduced"],
            ["chamber", "council"],
            ["legislator_id", "1"],
        ].forEach(([name, value]) => {
            const input = document.createElement("input");
            input.name = name;
            input.value = value;
            formElement.appendChild(input);
        });

        expect(new FormData(formElement).has("summary")).toBe(false);
        form.setData("summary" as never, "Set by an external form update" as never);
        rerender();

        const event = {
            preventDefault: vi.fn<() => void>(),
            currentTarget: formElement,
        } as unknown as React.SubmitEvent<HTMLFormElement>;

        act(() => result.current.onSubmit(event));

        expect(formState.setData).toHaveBeenCalledWith("summary", "Set by an external form update");
        expect(transformPayload).toBeDefined();
        const submitted = transformPayload?.(formState.data);
        expect(submitted?.summary).toBe("Set by an external form update");
        expect(submitted?.chamber).toBe("council");
        expect(submitted?.legislator_id).toBe(1);
    });
});
