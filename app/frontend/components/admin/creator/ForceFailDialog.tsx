import { router } from "@inertiajs/react";
import { useState } from "react";
import { notifyServerRefusal } from "app/frontend/components/admin/creator/notifyServerRefusal";
import { Button } from "app/frontend/components/ui/button";
import {
    Dialog,
    DialogContent,
    DialogDescription,
    DialogFooter,
    DialogHeader,
    DialogTitle,
} from "app/frontend/components/ui/dialog";
import { Input } from "app/frontend/components/ui/input";
import { Label } from "app/frontend/components/ui/label";

// @lat: [[bill-creator-pipeline-controls-panel#Why ForceFailDialog requires typing the confirm phrase]]

interface IProps {
    runId: number;
    open: boolean;
    onOpenChange: (open: boolean) => void;
}

const CONFIRM_PHRASE = "force fail";

const ForceFailDialog: React.FC<IProps> = ({ runId, open, onOpenChange }) => {
    const [phrase, setPhrase] = useState<string>("");
    const [posting, setPosting] = useState<boolean>(false);

    const canConfirm = phrase === CONFIRM_PHRASE && !posting;

    const handleOpenChange = (next: boolean) => {
        if (!next) {
            // @lat: [[bill-creator-pipeline-controls-panel#Why ForceFailDialog clears the typed phrase on any close path]]
            setPhrase("");
        }
        onOpenChange(next);
    };

    const handleConfirm = () => {
        if (!canConfirm) return;
        setPosting(true);
        router.post(
            `/pipeline_runs/${runId}/force_fail`,
            // @lat: [[bill-creator-pipeline-controls-panel#Why ForceFailDialog stays mounted when closed]]
            { confirm_phrase: CONFIRM_PHRASE, back_to: "bill_creator" },
            {
                preserveScroll: true,
                onSuccess: () => {
                    setPhrase("");
                    onOpenChange(false);
                },
                onFinish: () => setPosting(false),
                // @lat: [[bill-creator-pipeline-controls-panel#Why ForceFailDialog needs an explicit onError]]
                onError: (errors) => notifyServerRefusal(errors, "pipeline", "Could not force-fail this run."),
            },
        );
    };

    return (
        <Dialog open={open} onOpenChange={handleOpenChange}>
            <DialogContent data-testid="force-fail-dialog" className="w-[calc(100vw-2rem)] max-w-lg p-4 sm:p-6">
                <DialogHeader>
                    <DialogTitle>Force-fail this run?</DialogTitle>
                    <DialogDescription>
                        This will immediately mark the run as failed. Type <strong>force fail</strong> to confirm.
                    </DialogDescription>
                </DialogHeader>
                <div className="flex flex-col gap-2">
                    <Label htmlFor="force-fail-confirm">Type &quot;force fail&quot; to confirm</Label>
                    <Input
                        id="force-fail-confirm"
                        data-testid="input-force-fail-confirm"
                        value={phrase}
                        onChange={(e) => setPhrase(e.target.value)}
                        disabled={posting}
                        autoComplete="off"
                        spellCheck={false}
                        className="min-h-[44px]"
                    />
                </div>
                <DialogFooter className="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
                    <Button
                        type="button"
                        variant="outline"
                        onClick={() => handleOpenChange(false)}
                        disabled={posting}
                        className="min-h-[44px] w-full sm:w-auto"
                    >
                        Cancel
                    </Button>
                    <Button
                        type="button"
                        variant="destructive"
                        onClick={handleConfirm}
                        disabled={!canConfirm}
                        data-testid="btn-force-fail-confirm"
                        className="min-h-[44px] w-full sm:w-auto"
                    >
                        Force fail
                    </Button>
                </DialogFooter>
            </DialogContent>
        </Dialog>
    );
};

export default ForceFailDialog;
