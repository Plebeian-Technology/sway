/** @format */

import { useCallback, useState } from "react";

interface IProps {
  title?: string;
  children: React.ReactNode;
}

const DEFAULT_IMAGES = [
  "/assets/Sway1.png",
  "/assets/Sway7.png",
  "/assets/Sway3.png",
  "/assets/Sway4.png",
  "/assets/Sway5.png",
  "/assets/Sway6.png",
  "/assets/Sway2.png",
  "/assets/Sway8.png",
  "/assets/Sway5.png",
  "/assets/Sway8.png",
];

const LoginBubbles: React.FC<IProps> = ({ title, children }) => {
  const [images, setImages] = useState<string[]>(DEFAULT_IMAGES);

  const handleClick = useCallback((index: number) => {
    try {
      const rand = Math.floor(Math.random() * Math.floor(9));
      setImages((current) =>
        current.map((img, idx) => {
          if (idx === index) {
            return `/assets/bubbles/${rand}.png`;
          }
          return img;
        }),
      );
    } catch (error) {}
  }, []);

  return (
    <div className={"wrapper-login-hoc col pt-5 vh-100"}>
      <div className="container container-login-hoc">
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
