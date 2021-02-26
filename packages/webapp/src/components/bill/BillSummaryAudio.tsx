import { IconButton, Typography } from "@material-ui/core";
import { Hearing } from "@material-ui/icons";

const BillSummaryAudio = ({
    swayAudioBucketPath,
    swayAudioByline,
}: {
    swayAudioBucketPath: string;
    swayAudioByline: string;
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
        <div>
            <IconButton
                style={{
                    paddingTop: 0,
                    paddingBottom: 0,
                    paddingRight: 0,
                    paddingLeft: 5,
                }}
                onClick={play}
            >
                <Hearing />
            </IconButton>
            <Typography>{swayAudioByline}</Typography>
        </div>
    );
};

export default BillSummaryAudio;
