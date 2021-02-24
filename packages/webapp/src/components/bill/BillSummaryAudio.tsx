import { IconButton } from "@material-ui/core";
import { Hearing } from "@material-ui/icons";

const BillSummaryAudio = ({
    swayAudioBucketPath,
}: {
    swayAudioBucketPath: string;
}) => {
    const audio = new Audio(swayAudioBucketPath);
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
        <IconButton style={{ paddingLeft: 5 }} onClick={play}>
            <Hearing />
        </IconButton>
    );
};

export default BillSummaryAudio;
