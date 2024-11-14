import { useLocale } from "app/frontend/hooks/useLocales";
import { isCongressLocale } from "app/frontend/sway_utils";

import DateField from "app/frontend/components/admin/creator/fields/DateField";
import LocaleField from "app/frontend/components/admin/creator/fields/LocaleField";
import OrganizationsField from "app/frontend/components/admin/creator/fields/OrganizationsField";
import SelectField from "app/frontend/components/admin/creator/fields/SelectField";
import Separator from "app/frontend/components/admin/creator/fields/Separator";
import SummaryField from "app/frontend/components/admin/creator/fields/SummaryField";
import TextAreaField from "app/frontend/components/admin/creator/fields/TextAreaField";
import TextField from "app/frontend/components/admin/creator/fields/TextField";
import { forwardRef } from "react";
import { sway } from "sway";

interface IProps {
    swayField: sway.IFormField;
    fieldGroup: sway.IFormField[];
}

const BillCreatorField = forwardRef(
    ({ swayField, fieldGroup: { length: fieldGroupLength } }: IProps, summaryRef: React.Ref<string>) => {
        const [locale] = useLocale();

        if (swayField.name === "senateVoteDateTimeUtc" && !isCongressLocale(locale)) {
            return null;
        }

        const props = {
            swayField,
            fieldGroupLength,
        };

        switch (swayField.component) {
            case "separator":
                return <Separator {...props} />;

            case "text":
                return <TextField {...props} />;

            case "generatedText":
                return <TextField {...props} />;

            case "textarea":
                if (swayField.name === "summary") {
                    return <SummaryField ref={summaryRef} {...props} />;
                }
                if (swayField.name === "summaryPreview") {
                    return null;
                }
                return <TextAreaField {...props} />;

            case "date":
                return <DateField {...props} />;

            case "select":
                if (swayField.name.startsWith("organizations")) {
                    return <OrganizationsField {...props} />;
                } else if (swayField.name === "localeName") {
                    return <LocaleField {...props} />;
                } else {
                    return <SelectField {...props} />;
                }
            default:
                console.warn("BillCreatorField.switch - NO FIELD FOR SWAY FIELD COMPONENT + NAME", swayField);
                return null;
        }
    },
);

export default BillCreatorField;
