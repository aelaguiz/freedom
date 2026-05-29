import { spawn } from "node:child_process";
import os from "node:os";

import { defaultRelayLogger } from "./dock-relay-logger.mjs";

const BONJOUR_SERVICE_TYPE = "_codexdock._tcp";
const BONJOUR_DOMAIN = "local";

function bonjourServiceName(name = `Codex Dock ${os.hostname()}`) {
  return String(name)
    .replace(/[\r\n]/g, " ")
    .trim()
    .slice(0, 63) || "Codex Dock";
}

function bonjourTxtRecords(config) {
  const records = [
    `version=${config.version}`,
  ];
  if (config.hostId) {
    records.push(`relay-id=${String(config.hostId).replace(/[\r\n]/g, " ").trim().slice(0, 255)}`);
  }
  return records;
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
  const logger = config.logger || defaultRelayLogger;

  const child = spawn("dns-sd", buildBonjourAdvertisementArgs(config), {
    stdio: "ignore",
  });
  child.on("error", (error) => {
    logger.error("bonjour.advertisement_failed", {
      error,
      port: config.port,
      serviceType: config.bonjourType || BONJOUR_SERVICE_TYPE,
    });
  });
  logger.info("bonjour.advertisement_started", {
    port: config.port,
    serviceType: config.bonjourType || BONJOUR_SERVICE_TYPE,
  });
  return child;
}

export {
  buildBonjourAdvertisementArgs,
  startBonjourAdvertisement,
};
