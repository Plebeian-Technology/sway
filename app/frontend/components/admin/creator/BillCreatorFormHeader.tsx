import { router } from "@inertiajs/react";
import { TempBillStorage } from "app/frontend/components/bill/creator/TempBillStorage";
import { ROUTES } from "app/frontend/sway_constants";
import { fieldDisplayName } from "app/frontend/components/admin/creator/fieldDisplayName";
import { Save } from "lucide-react";
import { Button } from "app/frontend/components/ui/button";

interface IProps {
    storage: TempBillStorage;
    blurredFieldName?: string;
    processing?: boolean;
    onReset?: () => void;
    onResetForm?: () => void;
}

// @lat: [[bill-creator-field-display-labels#Why BillCreatorFormHeader is the V2 form header]]
const BillCreatorFormHeader: React.FC<IProps> = ({ storage, blurredFieldName, processing, onReset, onResetForm }) => {
    return (
        <div className="sticky top-0 z-20 flex flex-col items-center gap-3 border-b border-border-soft bg-background/95 py-2 backdrop-blur-xs md:static md:flex-row md:justify-between md:border-b-0 md:bg-transparent md:py-0">
            <div
                className={`text-xs uppercase tracking-wide text-muted-foreground ${
                    blurredFieldName ? "visible" : "invisible"
                }`}
            >
                {/* @lat: [[bill-creator-field-display-labels#Why the "Stored temporary" indicator uses fieldDisplayName instead of the raw field name]] */}
                Stored temporary {storage.name()} field:{" "}
                <b className="font-semibold text-foreground">
                    {blurredFieldName ? fieldDisplayName(blurredFieldName) : ""}
                </b>
            </div>
            {/* @lat: [[bill-creator-shell#How the frame adapts to phone browser viewports]] */}
            <div className="flex w-full flex-wrap justify-center gap-2 sm:w-auto">
                <Button type="submit" disabled={processing} className="min-h-11 w-full sm:w-auto md:min-h-0">
                    <Save aria-hidden />
                    &nbsp;Save
                </Button>
                <Button
                    type="button"
                    variant="outline"
                    className="min-h-11 w-full sm:w-auto md:min-h-0"
                    onClick={() => {
                        storage.remove();
                        onResetForm?.();
                        onReset?.();
                        // @lat: [[carried-run-pin-single-param-design#Why "Don't Save + Reset to New" carries nothing forward]]
                        router.get(ROUTES.billCreator);
                    }}
                >
                    Don&apos;t Save + Reset to New
                </Button>
            </div>
        </div>
    );
};

export default BillCreatorFormHeader;
