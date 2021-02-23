import { useEffect, useMemo } from "react";

interface IProps {
    children: JSX.Element[] | JSX.Element;
}

const COLORS = [
    "#00FF73  ",
    "#6C4AE2",
    "#FDDA00 ",
    "#DB27DB ",
    "#FA405A ",
    "#51EFFC ",
    "#EB640A ",
];

const ConfettiItem = () => {
    const w = Math.floor(Math.random() * 5);
    const h = w * 1.2;
    const x = Math.floor(Math.random() * 100);
    const y = Math.floor(Math.random() * 40);
    const c = COLORS[Math.floor(Math.random() * COLORS.length)];

    return (
        <div
            className="confetti"
            style={{
                top: `${y}%`,
                left: `${x}%`,
                width: `${w}%`,
                height: `${h}%`,
            }}
        >
            <div className="rotate">
                <div
                    className="askew"
                    style={{
                        backgroundColor: c,
                    }}
                ></div>
            </div>
        </div>
    );
};

const NUMBER_CONFETTIS = 200;
const Confetti: React.FC<IProps> = ({ children }) => {
    const tada = new Audio(
        "https://freesound.org/data/previews/397/397353_4284968-lq.mp3",
    );
    tada.load();

    const confettis = useMemo(() => {
        const _confettis = [];
        for (let i = 0; i < NUMBER_CONFETTIS; i++) {
            _confettis.push(<ConfettiItem key={i} />);
        }
        return _confettis;
    }, []);

    useEffect(() => {
        tada.play().catch(console.error);
    }, []);

    return (
        <div id="confetti-container">
            {confettis}
            {children}
        </div>
    );
};

export default Confetti;
