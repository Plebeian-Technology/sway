import type { InertiaFormProps } from "@inertiajs/react";
import { IApiBillCreator } from "app/frontend/components/admin/creator/types";
import { buildBillCreatorBody } from "app/frontend/components/admin/creator/utils/buildBillCreatorBody";
import { notify } from "app/frontend/sway_utils";
import { pageExpired } from "app/frontend/sway_utils/pageExpired";
import { useCallback } from "react";

const REQUIRED_FIELDS: ReadonlyArray<[keyof IApiBillCreator, string]> = [
    ["status", "Please select the bill status before saving."],
    ["chamber", "Please select the bill chamber before saving."],
    ["legislator_id", "Please select the bill sponsor before saving."],
];

interface IUseBillFormSubmit {
    form: InertiaFormProps<IApiBillCreator>;
    initialValues: IApiBillCreator;
    // @lat: [[bill-interesting-score#The bill interesting score#Why locale selection stays in the shell]]
    swayLocaleId?: number;
    onSaved: () => void;
}

export const useBillFormSubmit = ({
    form,
    initialValues,
    swayLocaleId,
    onSaved,
}: IUseBillFormSubmit): {
    onSubmit: React.SubmitEventHandler<HTMLFormElement>;
} => {
    const { setData, transform, post, put } = form;

    const onSubmit = useCallback<React.SubmitEventHandler<HTMLFormElement>>(
        (e) => {
            e.preventDefault();

            if (!swayLocaleId) {
                notify({ level: "error", title: "Please select a locale before saving." });
                return;
            }

            const formData = new FormData(e.currentTarget);
            const rawData = Object.fromEntries(formData.entries()) as unknown as IApiBillCreator;
            const body = buildBillCreatorBody(rawData, form.data.summary ?? "", swayLocaleId);

            for (const [field, message] of REQUIRED_FIELDS) {
                if (!body[field]) {
                    notify({ level: "error", title: message });
                    return;
                }
            }

            Object.keys(body).forEach((key) => {
                setData(key as keyof IApiBillCreator, (body as unknown as Record<string, unknown>)[key] as never);
            });

            const isUpdate = Boolean(initialValues.id);
            transform((current) => ({ ...current, ...body, news_usage: body.news_usage ?? "none" }));

            const requestOptions: NonNullable<Parameters<typeof post>[1]> = {
                preserveScroll: true,
                // @lat: [[identity-and-access#Identity and access#Sessions, cookies and bearer tokens#A refused CSRF write leaves a fresh retry path]]
                onSuccess: (page) => {
                    if (pageExpired(page)) {
                        notify({
                            level: "error",
                            title: "The page expired, so nothing was saved. Try again.",
                        });
                        return;
                    }
                    onSaved();
                },
            };

            // @lat: [[bill-creator-shell#The Bill Creator shell#Why a bill save carries its own return tab]]
            if (isUpdate) {
                put(`/bills/${initialValues.id}`, requestOptions);
            } else {
                post("/bills", requestOptions);
            }
        },
        [form.data.summary, setData, transform, post, put, swayLocaleId, initialValues.id, onSaved],
    );

    return { onSubmit };
};
