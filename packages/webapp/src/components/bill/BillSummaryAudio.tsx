import { GOOGLE_STATIC_ASSETS_BUCKET } from "@sway/constants";
import { Button } from "react-bootstrap";
import { FaAssistiveListeningSystems } from "react-icons/fa";

const BillSummaryAudio: React.FC<{
    localeName: string;
    swayAudioBucketPath: string;
    swayAudioByline: string;
}> = ({ localeName, swayAudioBucketPath, swayAudioByline }) => {
    const getAudioUrl = () => {
        if (swayAudioBucketPath.startsWith("http")) {
            return swayAudioBucketPath;
        }
        return `${GOOGLE_STATIC_ASSETS_BUCKET}/${localeName}%2Faudio%2F${swayAudioBucketPath}?alt=media`;
    };

    const audio = new Audio(getAudioUrl());
    audio.load();

    const play = () => {
        if (audio.paused) {
            audio.play().catch(console.error);
        } else if (audio.played.length > 0) {
            audio.pause();
        } else {
            audio.play().catch(console.error);
        }
    };

    return (
        <div className="d-flex flex-row align-items-center pointer my-3" onClick={play}>
            <Button variant="outline-primary" className="text-start border-0 p-0 me-2 d-inline">
                <FaAssistiveListeningSystems size="1.3em" />
            </Button>
            <span className="bold">Audio from:</span>&nbsp;<span>{swayAudioByline}</span>
        </div>
    );
};

export default BillSummaryAudio;
