import { logDev } from "@sway/utils";
import { getDownloadURL, ref } from "firebase/storage";
import { useCallback, useEffect, useMemo, useState } from "react";
import { Button } from "react-bootstrap";
import { FaAssistiveListeningSystems } from "react-icons/fa";
import { storage } from "../../firebase";

const BillSummaryAudio: React.FC<{
    localeName: string;
    swayAudioBucketPath: string;
    swayAudioByline: string;
}> = ({ localeName, swayAudioBucketPath, swayAudioByline }) => {
    const [swayAudioBucketURL, setSwayAudioBucketURL] = useState<string | undefined>();

    logDev("BillSummaryAudio", {
        localeName,
        swayAudioBucketPath,
        swayAudioByline,
    });

    useEffect(() => {
        function loadURLToInputFiled() {
            const storageRef = ref(
                storage,
                swayAudioBucketPath.includes(localeName)
                    ? swayAudioBucketPath
                    : `${localeName}/audio/${swayAudioBucketPath}?alt=media`,
            );
            getDownloadURL(storageRef).then(setSwayAudioBucketURL).catch(console.error);
        }
        if (swayAudioBucketPath && localeName) {
            loadURLToInputFiled();
        }
    }, [localeName, swayAudioBucketPath]);

    const audio = useMemo(
        () => swayAudioBucketURL && new Audio(swayAudioBucketURL),
        [swayAudioBucketURL],
    );
    audio && audio.load();

    const play = useCallback(() => {
        if (!audio) return;

        if (audio.paused) {
            audio.play().catch(console.error);
        } else if (audio.played.length > 0) {
            audio.pause();
        } else {
            audio.play().catch(console.error);
        }
    }, [audio]);

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
