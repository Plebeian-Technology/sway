/** @format */

import { GITHUB_LINK, TWITTER_LINK } from "@sway/constants";
import { useState } from "react";
import { FiGithub, FiTwitter } from "react-icons/fi";

interface IProps {
    title?: string;
    children: React.ReactNode;
}

const LoginBubbles: React.FC<IProps> = ({ title, children }) => {
    const [images, setImages] = useState<string[]>([
        "/Sway1.png",
        "/Sway7.png",
        "/Sway3.png",
        "/Sway4.png",
        "/Sway5.png",
        "/Sway6.png",
        "/Sway2.png",
        "/Sway8.png",
        "/Sway5.png",
        "/Sway8.png",
    ]);

    const handleClick = (index: number) => {
        try {
            const rand = Math.floor(Math.random() * Math.floor(9));
            setImages(
                images.map((img, idx) => {
                    if (idx === index) {
                        return `/bubbles/${rand}.png`;
                    }
                    return img;
                }),
            );
        } catch (error) {}
    };

    const openLink = (link: string) => {
        window.open(link, "_blank");
    };

    return (
        <div className={"wrapper-login-hoc col pt-5 vh-100"}>
            <div className="container container-login-hoc">
                {title && <h1>{title}</h1>}
                {children}
            </div>
            <div className="d-flex flex-row justify-content-center text-muted">
                <FiTwitter
                    className="m-1 pointer"
                    size={"1.2em"}
                    style={{ zIndex: 100 }}
                    onClick={() => openLink(TWITTER_LINK)}
                />
                <FiGithub
                    className="m-1 pointer"
                    size={"1.2em"}
                    style={{ zIndex: 100 }}
                    onClick={() => openLink(GITHUB_LINK)}
                />
            </div>
            <ul className="bg-bubbles-login-hoc">
                {images.map((image: string, index: number) => {
                    return (
                        <li key={index} className="pointer" onClick={() => handleClick(index)}>
                            <img src={image} alt="sway bubble" className="sway-bubble" />
                        </li>
                    );
                })}
            </ul>
        </div>
    );
};

export default LoginBubbles;
