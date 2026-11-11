import SwayAudio from "app/frontend/components/SwayAudio";

const BillSummaryAudio: React.FC<{
    audio_bucket_path: string;
    audio_by_line: string;
}> = ({ audio_bucket_path, audio_by_line }) => {
    return (
        <div>
            <div>{audio_bucket_path && <SwayAudio filePath={audio_bucket_path} />}</div>
            <div>
                <span className="font-bold ms-2">Audio sourced from:</span>&nbsp;<span>{audio_by_line}</span>
            </div>
        </div>
    );
};

export default BillSummaryAudio;
