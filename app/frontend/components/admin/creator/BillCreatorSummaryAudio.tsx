import BillSummaryAudio from "app/frontend/components/bill/BillSummaryAudio";
import { IApiBillCreator } from "app/frontend/components/admin/creator/types";
import { useCallback, useState } from "react";
import { Headphones } from "lucide-react";
import { Button } from "app/frontend/components/ui/button";
import { Input } from "app/frontend/components/ui/input";
import { Label } from "app/frontend/components/ui/label";
import { useSwayFormContext } from "app/frontend/components/admin/creator/context/useSwayFormContext";
import DirectUploadDialog, { IDirectUploadResult } from "app/frontend/components/admin/creator/DirectUploadDialog";
import FeatureInfo from "app/frontend/components/admin/creator/FeatureInfo";
import { AUDIO_FIELD_LABELS } from "app/frontend/components/admin/creator/audioFieldLabels";

interface IProps {
    onBlur?: (e: React.FocusEvent<HTMLInputElement | HTMLTextAreaElement>) => void;
}

// @lat: [[bill-creator-summary-audio#Why this is a rebuild, and why audio_bucket_path holds either an upload or a link]]
const BillCreatorSummaryAudio: React.FC<IProps> = ({ onBlur }) => {
    const { data, setData } = useSwayFormContext<IApiBillCreator>();

    const audio_by_line = data.audio_by_line ?? "";
    const audio_bucket_path = data.audio_bucket_path ?? "";

    const [showUpload, setShowUpload] = useState<boolean>(false);

    const onChangeByLine = useCallback(
        (e: React.ChangeEvent<HTMLInputElement>) => setData("audio_by_line", e.target.value),
        [setData],
    );

    const onChangeBucketPath = useCallback(
        (e: React.ChangeEvent<HTMLInputElement>) => setData("audio_bucket_path", e.target.value),
        [setData],
    );

    const onUploaded = useCallback(
        ({ signedId, previewUrl }: IDirectUploadResult) => {
            // @lat: [[bill-creator-summary-audio#Why onUploaded writes the signed id straight into audio_bucket_path]]
            if (previewUrl) {
                URL.revokeObjectURL(previewUrl);
            }
            setData("audio_bucket_path", signedId);
            setShowUpload(false);
        },
        [setData],
    );

    return (
        <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
            <div className="flex flex-col gap-2">
                <div className="flex items-center gap-1.5">
                    {/* @lat: [[bill-creator-summary-audio#Why the label reads from AUDIO_FIELD_LABELS instead of being typed inline]] */}
                    <Label className="font-semibold" htmlFor="audio_bucket_path">
                        {AUDIO_FIELD_LABELS.audio_bucket_path}
                    </Label>
                    <FeatureInfo note="creator.audioSummary" />
                </div>
                <Button type="button" variant="outline" onClick={() => setShowUpload(true)}>
                    <Headphones aria-hidden />
                    {audio_bucket_path ? "Upload New Audio Summary" : "Upload Audio Summary"}
                </Button>
                <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">
                    or use an external source
                </p>
                <Input
                    id="audio_bucket_path"
                    name="audio_bucket_path"
                    type="text"
                    value={audio_bucket_path}
                    onChange={onChangeBucketPath}
                    onBlur={onBlur}
                    placeholder="https://..."
                />
                {audio_bucket_path && (
                    <div className="mt-2">
                        <BillSummaryAudio audio_bucket_path={audio_bucket_path} audio_by_line={audio_by_line} />
                    </div>
                )}
            </div>

            <div className="flex flex-col gap-2">
                <Label className="font-semibold" htmlFor="audio_by_line">
                    {AUDIO_FIELD_LABELS.audio_by_line}
                </Label>
                <Input
                    id="audio_by_line"
                    name="audio_by_line"
                    type="text"
                    value={audio_by_line}
                    onChange={onChangeByLine}
                    onBlur={onBlur}
                />
            </div>

            <DirectUploadDialog
                open={showUpload}
                onOpenChange={setShowUpload}
                fileName={data.external_id}
                currentFilePath={audio_bucket_path || null}
                accept="audio/*"
                title="Upload Audio Summary"
                onUploaded={onUploaded}
            />
        </div>
    );
};

export default BillCreatorSummaryAudio;
