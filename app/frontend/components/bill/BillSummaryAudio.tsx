import SwayAudio from "app/frontend/components/SwayAudio";

const BillSummaryAudio: React.FC<{
    audioBucketPath: string;
    audioByLine: string;
}> = ({ audioBucketPath, audioByLine }) => {
    
    // const audio = useMemo(() => {
    //     if (!audioBucketPath) return;

    //     if (audioBucketPath.startsWith("https://")) {
    //         const a = new Audio(audioBucketPath);
    //         a.autoplay = false;
    //         return a;
    //     } else {
    //         const a = new Audio(`${SWAY_ASSETS_BUCKET_BASE_URL}/${audioBucketPath}`);
    //         a.autoplay = false;
    //         return a;
    //     }
    // }, [audioBucketPath]);

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
            <div>{audioBucketPath && <SwayAudio filePath={audioBucketPath} />}</div>
            <div>
                <span className="bold ms-2">Audio sourced from:</span>&nbsp;<span>{audioByLine}</span>
            </div>
        </div>
    );
};

export default BillSummaryAudio;
