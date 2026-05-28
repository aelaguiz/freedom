import { spawn } from "node:child_process";
import os from "node:os";

const BONJOUR_SERVICE_TYPE = "_codexdock._tcp";
const BONJOUR_DOMAIN = "local";

function bonjourServiceName(name = `Codex Dock ${os.hostname()}`) {
  return String(name)
    .replace(/[\r\n]/g, " ")
    .trim()
    .slice(0, 63) || "Codex Dock";
}

function bonjourTxtRecords(config) {
  return [
    `version=${config.version}`,
    `auth=${config.phoneAuth}`,
    "scheme=ws",
  ];
}

function buildBonjourAdvertisementArgs(config) {
  return [
    "-R",
    bonjourServiceName(config.bonjourName),
    config.bonjourType || BONJOUR_SERVICE_TYPE,
    config.bonjourDomain || BONJOUR_DOMAIN,
    String(config.port),
    ...bonjourTxtRecords(config),
  ];
}

function startBonjourAdvertisement(config) {
  if (config.advertiseBonjour === false) {
    return null;
  }

  const child = spawn("dns-sd", buildBonjourAdvertisementArgs(config), {
    stdio: "ignore",
  });
  child.on("error", (error) => {
    console.error(`dock-relay: Bonjour advertisement failed: ${error.message || error}`);
  });
  return child;
}

export {
  buildBonjourAdvertisementArgs,
  startBonjourAdvertisement,
};
