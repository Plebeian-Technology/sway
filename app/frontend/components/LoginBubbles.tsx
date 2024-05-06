/** @format */

import { useCallback, useState } from "react";

interface IProps {
    title?: string;
    children: React.ReactNode;
    isBubbles?: boolean;
}

const DEFAULT_IMAGES = [
    "/images/Sway1.png",
    "/images/Sway7.png",
    "/images/Sway3.png",
    "/images/Sway4.png",
    "/images/Sway5.png",
    "/images/Sway6.png",
    "/images/Sway2.png",
    "/images/Sway8.png",
    "/images/Sway5.png",
    "/images/Sway8.png",
];

const LoginBubbles: React.FC<IProps> = ({ title, isBubbles, children }) => {
    const [images, setImages] = useState<string[]>(DEFAULT_IMAGES);

    const handleClick = useCallback((index: number) => {
        try {
            const rand = Math.floor(Math.random() * Math.floor(9));
            setImages((current) =>
                current.map((img, idx) => {
                    if (idx === index) {
                        return `/images/bubbles/${rand}.png`;
                    }
                    return img;
                }),
            );
        } catch (error) {}
    }, []);

    return (
        <div className={"container-login"}>
            <div className="container container-login-body">
                {title && <h1>{title}</h1>}
                {children}
            </div>
            {isBubbles && (
                <ul className="container-login-bubbles">
                    {images.map((image: string, index: number) => {
                        return (
                            <li key={index} className="pointer" onClick={() => handleClick(index)}>
                                {" "}
                                {/* NOSONAR */}
                                <img src={image} alt="sway bubble" className="sway-bubble" />
                            </li>
                        );
                    })}
                </ul>
            )}
        </div>
    );
};

export default LoginBubbles;
