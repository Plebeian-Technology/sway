/** @format */

import React from "react";
import { GITHUB_LINK, TWITTER_LINK } from "@sway/constants";
import sway1 from "../../assets/Sway1.png";
import sway2 from "../../assets/Sway2.png";
import sway4 from "../../assets/Sway4.png";
import sway5 from "../../assets/Sway5.png";
import SwaySvg from "../SwaySvg";

interface IProps {
    title?: string;
    children: React.ReactNode;
}

const LoginBubbles: React.FC<IProps> = ({ title, children }) => {
    const [images, setImages] = React.useState<string[]>([
        sway1,
        sway2,
        sway5,
        sway4,
        sway2,
        sway5,
        sway5,
        sway4,
        sway5,
        sway1,
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
                            style={{ cursor: "pointer" }}
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
