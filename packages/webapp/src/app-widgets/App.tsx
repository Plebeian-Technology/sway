import { createTheme, ThemeProvider } from "@mui/material";
import { IS_MOBILE_PHONE, swayDarkBlue } from "../utils";
import VoteWidget from "./VoteWidget";

const App = () => {
    const theme = createTheme({
        palette: {
            primary: {
                main: swayDarkBlue,
            },
        },
        typography: {
            fontFamily: [
                "Exo",
                "-apple-system",
                "BlinkMacSystemFont",
                '"Segoe UI"',
                "Roboto",
                '"Helvetica Neue"',
                "Arial",
                "sans-serif",
                '"Apple Color Emoji"',
                '"Segoe UI Emoji"',
                '"Segoe UI Symbol"',
            ].join(","),
        },
        components: {
            MuiInputBase: {
                styleOverrides: {
                    root: {
                        color: "inherit",
                    },
                    input: {
                        color: "inherit",
                    },
                },
            },
            MuiFormLabel: {
                styleOverrides: {
                    root: {
                        color: "inherit",
                        borderColor: "inherit",
                    },
                },
            },
            MuiOutlinedInput: {
                styleOverrides: {
                    notchedOutline: {
                        borderColor: "inherit",
                    },
                },
            },
            MuiToolbar: {
                styleOverrides: {
                    regular: {
                        minHeight: 50,
                    },
                },
            },
            MuiDialog: {
                styleOverrides: {
                    paper: {
                        margin: IS_MOBILE_PHONE ? "0px" : "32px", // 32px is default
                    },
                },
            },
        },
    });

    return (
        <ThemeProvider theme={theme}>
            <VoteWidget />
        </ThemeProvider>
    );
};

export default App;
