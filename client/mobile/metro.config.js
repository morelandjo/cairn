const { getDefaultConfig } = require("expo/metro-config");
const path = require("path");

const config = getDefaultConfig(__dirname);

// Resolve proto from monorepo root
config.watchFolders = [path.resolve(__dirname, "../../proto")];
config.resolver.nodeModulesPaths = [
  path.resolve(__dirname, "node_modules"),
  path.resolve(__dirname, "../../proto/node_modules"),
];

module.exports = config;
