/** @format */

import Icon from "@material-ui/core/Icon";
import { createStyles, makeStyles } from "@material-ui/styles";
import { sway } from "sway";
import React from "react";
import { OverridableComponent } from "@material-ui/core/OverridableComponent";
import { SvgIconTypeMap } from "@material-ui/core";

const useStyles = makeStyles(() => {
    return createStyles({
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
});


export type TSwaySvg = OverridableComponent<SvgIconTypeMap<Record<string, unknown>, "svg">>

interface IProps extends sway.IPlainObject {
    src: string;
    alt?: string;
    style?: sway.IPlainObject;
    containerStyle?: sway.IPlainObject;
    handleClick?: (e: React.MouseEvent<HTMLElement>) => void;
}

const SwaySvg: React.FC<IProps> = ({ src, alt, containerStyle, style, handleClick }) => {
    const classes = useStyles();

    return (
        <div style={{ margin: "10px", ...containerStyle }} onClick={handleClick && handleClick}>
            <Icon classes={{ root: classes.iconRoot }} style={style && style}>
                <img
                    className={classes.imageIcon}
                    src={src}
                    alt={alt ? alt : "icon"}
                />
            </Icon>
        </div>
    );
};

export default SwaySvg;
