/** @format */

import { useState } from "react";
import { GITHUB_LINK, TWITTER_LINK } from "@sway/constants";
import SwaySvg from "../SwaySvg";
import { Image } from "react-bootstrap";

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
        <div className={"wrapper-login-hoc col"}>
            <div className="row">
                <div className="col-8">&nbsp;</div>
                <div onClick={() => openLink(TWITTER_LINK)} className="col-2 px-0">
                    <Image
                        thumbnail
                        src={"/icons/twitter.svg"}
                        className="bg-transparent border-0 w-50 text-end pe-0"
                    />
                </div>

                <div onClick={() => openLink(GITHUB_LINK)} className="col-2 ps-0">
                    <Image
                        thumbnail
                        src={"/icons/github.svg"}
                        className="bg-transparent border-0 w-50 text-end ps-0"
                    />
                </div>
            </div>
            <div className="container-login-hoc">
                {title && <h1>{title}</h1>}
                {children}
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
