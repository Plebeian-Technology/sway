import { Pencil, Plus, X } from "lucide-react";
import { useCallback, useState } from "react";
import { Button } from "app/frontend/components/ui/button";
import DirectUploadDialog, { IDirectUploadResult } from "app/frontend/components/admin/creator/DirectUploadDialog";

interface IProps {
    label: string;
    iconUrl?: string | null;
    onUploaded: (upload: IDirectUploadResult) => void;
    onRemove?: () => void;
}

// @lat: [[bill-creator-organizations-panel#Why OrgIconUpload sends nothing to the server itself]]
const OrgIconUpload: React.FC<IProps> = ({ label, iconUrl, onUploaded, onRemove }) => {
    const [open, setOpen] = useState<boolean>(false);

    const handleUploaded = useCallback(
        (upload: IDirectUploadResult) => {
            onUploaded(upload);
            setOpen(false);
        },
        [onUploaded],
    );

    const hasIcon = Boolean(iconUrl);

    return (
        <div className="flex items-center gap-3">
            <div
                aria-hidden={!hasIcon}
                className="flex h-14 w-14 shrink-0 items-center justify-center overflow-hidden rounded-lg border-neo border-border-strong bg-muted shadow-neo"
            >
                {hasIcon ? (
                    <img src={iconUrl as string} alt={`${label} icon`} className="h-full w-full object-contain" />
                ) : (
                    <span className="text-xs font-semibold uppercase tracking-widest text-muted-foreground">
                        No icon
                    </span>
                )}
            </div>
            <div className="flex flex-wrap items-center gap-2">
                <Button type="button" variant="outline" size="sm" onClick={() => setOpen(true)}>
                    {hasIcon ? (
                        <>
                            <Pencil aria-hidden />
                            &nbsp;Update icon
                        </>
                    ) : (
                        <>
                            <Plus aria-hidden />
                            &nbsp;Add icon
                        </>
                    )}
                </Button>
                {hasIcon && onRemove && (
                    <Button type="button" variant="outline" size="sm" onClick={onRemove}>
                        <X aria-hidden />
                        &nbsp;Remove
                    </Button>
                )}
            </div>

            <DirectUploadDialog
                open={open}
                onOpenChange={setOpen}
                fileName={label}
                currentFilePath={iconUrl ?? null}
                accept="image/*"
                title={`Upload icon — ${label}`}
                onUploaded={handleUploaded}
            />
        </div>
    );
};

export default OrgIconUpload;
