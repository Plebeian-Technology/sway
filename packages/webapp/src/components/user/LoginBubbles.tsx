/** @format */

import { useState } from "react";
import { GITHUB_LINK, TWITTER_LINK } from "@sway/constants";
import SwaySvg from "../SwaySvg";

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
        window.open(link);
    };

    return (
        <div className={"wrapper-login-hoc"}>
            <div className="wrapper-social-icons">
                <div onClick={() => openLink(TWITTER_LINK)}>
                    <SwaySvg src={"/icons/twitter.svg"} />
                </div>

                <div onClick={() => openLink(GITHUB_LINK)}>
                    <SwaySvg src={"/icons/github.svg"} />
                </div>
            </div>
            <div className="container-login-hoc">
                {title && <h1>{title}</h1>}
                {children}
            </div>
            <ul className="bg-bubbles-login-hoc">
                {images.map((image: string, index: number) => {
                    return (
                        <li
                            key={index}
                            className="pointer"
                            onClick={() => handleClick(index)}
                        >
                            <img src={image} alt="sway bubble" />
                        </li>
                    );
                })}
            </ul>
        </div>
    );
};

export default LoginBubbles;
