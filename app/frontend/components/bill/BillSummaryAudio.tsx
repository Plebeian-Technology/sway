import SwayAudio from "app/frontend/components/SwayAudio";

const BillSummaryAudio: React.FC<{
    audio_bucket_path: string;
    audio_by_line: string;
}> = ({ audio_bucket_path, audio_by_line }) => {
    // const audio = useMemo(() => {
    //     if (!audio_bucket_path) return;

    //     if (audio_bucket_path.startsWith("https://")) {
    //         const a = new Audio(audio_bucket_path);
    //         a.autoplay = false;
    //         return a;
    //     } else {
    //         const a = new Audio(`${SWAY_ASSETS_BUCKET_BASE_URL}/${audio_bucket_path}`);
    //         a.autoplay = false;
    //         return a;
    //     }
    // }, [audio_bucket_path]);

    // const [isPlaying, setPlaying] = useState<boolean>(false);

    // const play = useCallback(() => {
    //     if (!audio) return;

    //     if (audio.paused) {
    //         audio
    //             .play()
    //             .then(() => setPlaying(true))
    //             .catch(console.error);
    //     } else if (audio.played.length > 0) {
    //         audio.pause();
    //         setPlaying(false);
    //     } else {
    //         audio
    //             .play()
    //             .then(() => setPlaying(true))
    //             .catch(console.error);
    //     }
    // }, [audio]);

    return (
        <div className="col">
            {/* <Button onClick={play} disabled={!audio} variant="outline-primary">
                {isPlaying ? "Pause Audio Summary" : "Play Audio Summary"} <FaAssistiveListeningSystems size="1.3em" />
            </Button> */}
            <div>{audio_bucket_path && <SwayAudio filePath={audio_bucket_path} />}</div>
            <div>
                <span className="bold ms-2">Audio sourced from:</span>&nbsp;<span>{audio_by_line}</span>
            </div>
        </div>
    );
};

export default BillSummaryAudio;
