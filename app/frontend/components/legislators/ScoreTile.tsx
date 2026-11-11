type ScoreTone = "primary" | "destructive" | "neutral";

const TONE_CLASS: Record<ScoreTone, string> = {
    primary: "text-primary",
    destructive: "text-destructive",
    neutral: "text-foreground",
};

interface IProps {
    label: string;
    value: number | string;
    tone: ScoreTone;
}

const ScoreTile: React.FC<IProps> = ({ label, value, tone }) => (
    <div data-neo-surface="true" className="rounded-xl px-4 py-3">
        <div className="text-xs font-black uppercase tracking-widest text-muted-foreground">{label}</div>
        <div className={`mt-2 text-2xl font-black ${TONE_CLASS[tone]}`} style={{ fontVariantNumeric: "tabular-nums" }}>
            {value}
        </div>
    </div>
);

export default ScoreTile;
