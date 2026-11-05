import { timelockEncrypt, timelockDecrypt, mainnetClient, roundAt, roundTime, defaultChainInfo, Buffer } from "tlock-js";

// drand quicknet (mainnet, 3s rounds). Encryption is fully offline; only decryption needs the published beacon.
const client = mainnetClient();
const info = defaultChainInfo;

async function seal(text, unlockMs) {
  const round = roundAt(unlockMs, info);
  const ciphertext = await timelockEncrypt(round, Buffer.from(text, "utf8"), client);
  return { round, ciphertext, unlockMs: roundTime(info, round) };
}

async function unseal(ciphertext) {
  const buf = await timelockDecrypt(ciphertext, client);
  return buf.toString("utf8");
}

function roundFor(unlockMs) { return roundAt(unlockMs, info); }

const api = { seal, unseal, roundFor, chainHash: info.hash, periodSec: info.period };
if (typeof window !== "undefined") window.LaterTlock = api;
export default api;
