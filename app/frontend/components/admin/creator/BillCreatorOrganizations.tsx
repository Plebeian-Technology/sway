/** @format */

import { usePage } from "@inertiajs/react";

import BillCreatorFormHeader from "app/frontend/components/admin/creator/BillCreatorFormHeader";
import { useTempStorage } from "app/frontend/components/admin/creator/hooks/useTempStorage";
import {
    ICreatorOrganizations,
    IOrganizationErrors,
    TOrganizationError,
    TOrganizationOption,
} from "app/frontend/components/admin/creator/types";
import FormContext from "app/frontend/components/contexts/FormContext";
import SwaySpinner from "app/frontend/components/SwaySpinner";
import { useSearchParams } from "app/frontend/hooks/useSearchParams";
import { Support } from "app/frontend/sway_constants";
import { Fragment, useCallback, useEffect, useMemo } from "react";
import { Button, Form, FormLabel } from "react-bootstrap";
import { FiSave } from "react-icons/fi";
import { MultiValue } from "react-select";
import Creatable from "react-select/creatable";
import { sway } from "sway";
import { useInertiaForm } from "use-inertia-form";
import { notify, REACT_SELECT_STYLES, SWAY_STORAGE } from "../../../sway_utils";
import BillCreatorOrganization from "./BillCreatorOrganization";

const toCreatorOption = (organization: sway.IOrganization, billId: number) =>
    ({
        value: organization.id,
        label: organization.name,
        summary: organization.positions?.find((p) => p.billId === billId)?.summary,
        support: organization.positions?.find((p) => p.billId === billId)?.support ?? Support.For,
        icon_path: organization.iconPath,
    }) as TOrganizationOption;

const BillCreatorOrganizations: React.FC = () => {
    // @ts-expect-error - Property 'organizations' is missing in type 'Errors & ErrorBag' but required in type 'IOrganizationErrors'.
    const errors: IOrganizationErrors = usePage().props.errors;

    // eslint-disable-next-line react-hooks/exhaustive-deps
    const searchParams = useMemo(() => new URLSearchParams(window.location.search), [window.location.search]);

    const bill = usePage().props.bill as sway.IBill & { organizations: sway.IOrganization[] };
    const organizations = usePage().props.organizations as sway.IOrganization[];
    const billOrganizations = bill.organizations as sway.IOrganization[];

    const options = useMemo(
        () => (organizations ?? []).map((o) => toCreatorOption(o, bill.id)),
        [bill.id, organizations],
    );
    const optionsOnBill = useMemo(
        () => (billOrganizations ?? []).map((o) => toCreatorOption(o, bill.id)),
        [bill.id, billOrganizations],
    );

    const defaultValues = useMemo(() => ({ bill_id: bill.id, organizations: optionsOnBill }), [bill.id, optionsOnBill]);
    const form = useInertiaForm<ICreatorOrganizations>(defaultValues);
    const { data, setData, post } = form;

    const {
        storage,
        onBlur: _onBlur,
        blurredFieldName,
    } = useTempStorage(SWAY_STORAGE.Local.BillOfTheWeek.Organizations, data);

    const { remove } = useSearchParams();
    useEffect(() => {
        const saved = searchParams.get("saved");
        if (saved) {
            notify({ level: "success", title: saved });
            window.setTimeout(() => {
                remove("saved");
            }, 2000);
        }
    }, [remove, searchParams]);

    const handleSelectOrganization = useCallback(
        (newValues: MultiValue<TOrganizationOption>) => {
            if (newValues) {
                setData("organizations", newValues as TOrganizationOption[]);
            }
        },
        [setData],
    );

    const mappedSelectedOrgs = useMemo(
        () =>
            (data.organizations || []).map(
                (organization: TOrganizationOption, index: number, array: TOrganizationOption[]) => {
                    const isLastOrganization = index === array.length - 1;

                    return (
                        <Fragment key={`${organization.label}-${index}`}>
                            <BillCreatorOrganization
                                index={index}
                                organization={organization}
                                error={errors?.organizations?.[index] as TOrganizationError | undefined}
                            />
                            {isLastOrganization ? null : <hr />}
                        </Fragment>
                    );
                },
            ),
        [data.organizations, errors],
    );

    const handleCreateOption = useCallback(
        (name: string) => {
            setData(
                "organizations",
                data.organizations.concat({
                    value: -(data.organizations.length + 1),
                    label: name,
                    summary: "",
                    support: Support.For,
                }),
            );
        },
        [data.organizations, setData],
    );

    const onSubmit = useCallback(
        (e: React.FormEvent) => {
            e.preventDefault();

            if (!bill.id) {
                notify({
                    level: "error",
                    title: "Click Save on the Details and Summary tab before clicking save here.",
                });
                return;
            }

            post("/organizations", { preserveScroll: true, async: true });
        },
        [bill.id, post],
    );

    return (
        <FormContext.Provider value={form}>
            <Form onSubmit={onSubmit}>
                <BillCreatorFormHeader form={form} storage={storage} blurredFieldName={blurredFieldName} />
                <div className="col">
                    <div className="row">
                        <div className="col">
                            <FormLabel className="bold">Organizations (Optional)</FormLabel>
                            <Creatable
                                isMulti
                                isClearable
                                isSearchable
                                name={"organizations"}
                                value={data.organizations || []}
                                options={options}
                                onCreateOption={handleCreateOption}
                                onChange={handleSelectOrganization}
                                isDisabled={false}
                                styles={REACT_SELECT_STYLES}
                            />
                        </div>
                    </div>
                    <div className="row">
                        <div className="col">{mappedSelectedOrgs}</div>
                    </div>
                </div>
                <div className="mx-auto text-center p-5">
                    <div className="row align-items-center">
                        <div className="col text-center">
                            <Button
                                disabled={form.processing}
                                variant="primary"
                                size="lg"
                                type="submit"
                                className="p-5 w-100 my-5"
                            >
                                <FiSave />
                                &nbsp;Save Supporting/Opposing Arguments
                            </Button>
                        </div>
                    </div>
                </div>
                <div className="row align-items-center mt-3">
                    <div className="col text-center">
                        <SwaySpinner isHidden={!form.processing} />
                    </div>
                </div>
            </Form>
        </FormContext.Provider>
    );
};

export default BillCreatorOrganizations;
