import React from "react";

interface IProps {
    // @lat: [[locale-flag-not-seal-design#Where flag files live]]
    swayLocaleSlug: string;
    className?: string;
}

// @lat: [[locale-flag-not-seal-design#Why SwayLocaleFlag is a flag, never a seal]]
const SwayLocaleFlag: React.FC<IProps> = ({ swayLocaleSlug, className }) => {
    return (
        <img
            src={`/images/flags/${swayLocaleSlug}.svg`}
            alt=""
            aria-hidden="true"
            className={className}
            // @lat: [[locale-flag-not-seal-design#Why the flag image is hidden with onLoad and onError instead of useEffect]]
            onLoad={(event) => {
                event.currentTarget.style.display = "";
            }}
            onError={(event) => {
                event.currentTarget.style.display = "none";
            }}
        />
    );
};

export default SwayLocaleFlag;
