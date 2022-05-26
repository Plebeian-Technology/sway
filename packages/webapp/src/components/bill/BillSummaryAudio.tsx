import { GOOGLE_STATIC_ASSETS_BUCKET } from "@sway/constants";
import { Button } from "react-bootstrap";
import { FaAssistiveListeningSystems } from "react-icons/fa";

const BillSummaryAudio: React.FC<{
    localeName: string;
    swayAudioBucketPath: string;
    swayAudioByline: string;
}> = ({ localeName, swayAudioBucketPath, swayAudioByline }) => {
    // photoURL: `${GOOGLE_STATIC_ASSETS_BUCKET}/washington-district_of_columbia-united_states%2Flegislators%2Fnadeau_1.jpg?alt=media`,
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
        <div className="row pointer align-items-center" onClick={play}>
            <div className="col-2 pe-0">
                <Button variant="outline-primary" className="border-0">
                    <FaAssistiveListeningSystems size="1.3em" />
                </Button>
            </div>
            <div className="col-10">
                <span className="bold">Audio from:</span> {swayAudioByline}
            </div>
        </div>
    );
};

export default BillSummaryAudio;
