module.exports = {
    reactScriptsVersion: "react-scripts" /* (default value) */,
    webpack: {
        configure: (webpackConfig) => {
            webpackConfig["module"]["rules"] = [
                ...webpackConfig["module"]["rules"],
                {
                    enforce: "pre",
                    test: /\.js$/,
                    loader: "source-map-loader",
                    exclude: /node_modules\/@firebase/, //to exclude firebase from source-map
                    // exclude: /node_modules\/@firebase\/auth/ //to just exclude firebase auth from source-map
                },
            ];

            return webpackConfig;
        },
    },
};
