import { IconButton, Typography } from "@material-ui/core";
import { Hearing } from "@material-ui/icons";
import CenteredDivRow from "../shared/CenteredDivRow";

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
        <CenteredDivRow
            style={{ paddingLeft: 15, cursor: "pointer" }}
            onClick={play}
        >
            <IconButton
                style={{
                    padding: 0,
                }}
            >
                <Hearing />
            </IconButton>
            <Typography>{swayAudioByline}</Typography>
        </CenteredDivRow>
    );
};

export default BillSummaryAudio;
