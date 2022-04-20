/** @format */

import { SvgIconTypeMap } from "@mui/material";
import Icon from "@mui/material/Icon";
import { OverridableComponent } from "@mui/material/OverridableComponent";
import { makeStyles } from "@mui/styles";
import React from "react";
import { sway } from "sway";

const useStyles = makeStyles({
    imageIcon: {
        display: "flex",
        height: "inherit",
        width: "inherit",
    },
    iconRoot: {
        textAlign: "center",
        cursor: "pointer",
    },
});

export type TSwaySvg = OverridableComponent<SvgIconTypeMap<Record<string, unknown>, "svg">>;

interface IProps extends sway.IPlainObject {
    src: string;
    alt?: string;
    style?: React.CSSProperties;
    containerStyle?: React.CSSProperties;
    handleClick?: (e: React.MouseEvent<HTMLElement>) => void;
}

const SwaySvg: React.FC<IProps> = ({ src, alt, containerStyle, style, handleClick }) => {
    const classes = useStyles();

    return (
        <div style={{ margin: "10px", ...containerStyle }} onClick={handleClick && handleClick}>
            <Icon classes={{ root: classes.iconRoot }} style={style && style}>
                <img className={classes.imageIcon} src={src} alt={alt ? alt : "icon"} />
            </Icon>
        </div>
    );
};

interface IIconProps {
    src: string;
    alt?: string;
    style?: sway.IPlainObject;
    handleClick?: (e: React.MouseEvent<HTMLElement>) => void;
}

const useIconStyles = makeStyles({
    imageIcon: {
        height: "100%",
    },
    iconRoot: {
        textAlign: "center",
    },
});

export const SwaySvgIcon: React.FC<IIconProps> = ({ src, alt, handleClick, style }) => {
    const classes = useIconStyles();
    return (
        <Icon classes={{ root: classes.iconRoot }} onClick={handleClick}>
            <img className={classes.imageIcon} src={src} alt={alt} style={style} />
        </Icon>
    );
};

export default SwaySvg;
