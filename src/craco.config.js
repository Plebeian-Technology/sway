// eslint-disable-next-line
const path = require("path");

module.exports = {
    reactScriptsVersion: "react-scripts" /* (default value) */,
    webpack: {
        configure: (webpackConfig) => {
            webpackConfig["module"]["rules"] = [
                ...webpackConfig["module"]["rules"],
                {
                    enforce: "pre",
                    exclude: [
                        // path.resolve(__dirname, "node_modules/@firebase"),
                        // path.resolve(__dirname, "node_modules/@firebase/auth/dist/*.js"),
                        path.resolve(
                            __dirname,
                            "node_modules/@firebase/auth/dist/*",
                        ),
                    ],
                    // exclude: /node_modules\/@firebase\/auth/ //to just exclude firebase auth from source-map
                    test: /\.(js|map)$/,
                    loader: path.resolve(
                        __dirname,
                        "node_modules/source-map-loader/dist/cjs.js",
                    ),
                    // loader: path.resolve(__dirname, "node_modules/source-map-loader"),
                    // loader: "source-map-loader",
                },
            ];
            return webpackConfig;
        },
    },
};
