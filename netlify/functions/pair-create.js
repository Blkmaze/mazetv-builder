// Called by the TV app: mint a short code and an empty pairing slot.
const { getStore } = require("@netlify/blobs");
const { json } = require("./_gh");

function makeCode() {
  const digits = "0123456789";
  let c = "";
  for (let i = 0; i < 6; i++) c += digits[Math.floor(Math.random() * 10)];
  return c;
}

exports.handler = async () => {
  const store = getStore("mazetv-pairing");
  let code;
  for (let i = 0; i < 5; i++) {
    code = makeCode();
    const existing = await store.get(code);
    if (!existing) break; // collision is astronomically unlikely, but check anyway
  }
  await store.setJSON(code, { claimed: false, createdAt: Date.now() }, { metadata: { ttl: "600" } });
  return json(200, { code });
};
