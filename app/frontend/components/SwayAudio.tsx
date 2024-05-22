import { SWAY_ASSETS_BUCKET_BASE_URL } from "app/frontend/sway_constants/google_cloud_storage";
import { useRef } from "react";

const SwayAudio: React.FC<{ filePath: string }> = ({ filePath }) => {
    const ref = useRef<HTMLAudioElement | null>(null);
    // const audioContext = new AudioContext();
    return (
        <>
            <audio
                controls
                ref={ref}
                src={filePath.startsWith("https://") ? filePath : `${SWAY_ASSETS_BUCKET_BASE_URL}/${filePath}`}
            ></audio>
            {/* {ref.current && audioContext.createMediaElementSource(ref.current)} */}
        </>
    );
};

export default SwayAudio;