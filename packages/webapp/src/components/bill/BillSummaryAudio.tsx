import { IconButton, Typography } from "@mui/material";
import { Hearing } from "@mui/icons-material";
import { GOOGLE_STATIC_ASSETS_BUCKET } from "@sway/constants";
import CenteredDivRow from "../shared/CenteredDivRow";

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
