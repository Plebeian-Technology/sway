import { SWAY_ASSETS_BUCKET_BASE_URL } from "app/frontend/sway_constants/google_cloud_storage";
import { reportOnce } from "app/frontend/sway_utils/report_once";
import { useRef } from "react";

interface IProps {
    filePath: string;
}

const reportMissingBucket = () =>
    reportOnce(
        "sway-audio-missing-assets-bucket",
        "SwayAudio has no assets bucket. The image was built without VITE_SWAY_ASSETS_BUCKET, so no audio can play.",
    );

const SwayAudio: React.FC<IProps> = ({ filePath }) => {
    const ref = useRef<HTMLAudioElement | null>(null);

    const isAbsolute = filePath.startsWith("https://");

    if (!isAbsolute && !SWAY_ASSETS_BUCKET_BASE_URL) {
        // @lat: [[sway-google-cloud-storage-design#Why SwayAudio reports a missing bucket to Sentry instead of a useEffect]]
        reportMissingBucket();
        return null;
    }

    return (
        <audio controls ref={ref} src={isAbsolute ? filePath : `${SWAY_ASSETS_BUCKET_BASE_URL}/${filePath}`}>
            <track kind="captions" srcLang="en" label="English" />
        </audio>
    );
};

export default SwayAudio;
