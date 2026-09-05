// Polled by the TV app until the code above has been claimed.
const { getStore } = require("@netlify/blobs");
const { json } = require("./_gh");

exports.handler = async (event) => {
  const code = (event.queryStringParameters || {}).code || "";
  if (!/^\d{6}$/.test(code)) return json(400, { error: "Bad code" });

  const store = getStore("mazetv-pairing");
  const slot = await store.get(code, { type: "json" });
  if (!slot) return json(404, { error: "expired" });
  if (!slot.claimed) return json(404, { error: "not claimed yet" });

  // One-time use: delete right after handing the credentials back.
  await store.delete(code);
  return json(200, slot);
};
