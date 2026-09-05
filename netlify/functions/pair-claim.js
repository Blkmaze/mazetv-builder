// Called by the companion web page: attach real credentials to a code
// someone already typed in on the TV.
const { getStore } = require("@netlify/blobs");
const { json } = require("./_gh");

exports.handler = async (event) => {
  if (event.httpMethod !== "POST") return json(405, { error: "POST only" });
  try {
    const b = JSON.parse(event.body || "{}");
    const code = (b.code || "").trim();
    if (!/^\d{6}$/.test(code)) return json(400, { error: "Enter the 6-digit code shown on your TV" });

    const store = getStore("mazetv-pairing");
    const slot = await store.get(code, { type: "json" });
    if (!slot) return json(404, { error: "That code has expired. Go back to the TV and get a new one." });

    await store.setJSON(code, {
      claimed: true,
      type: b.type === "m3u" ? "m3u" : "xtream",
      host: (b.host || "").trim(),
      username: (b.username || "").trim(),
      password: (b.password || "").trim(),
      createdAt: slot.createdAt,
    });
    return json(200, { ok: true });
  } catch (e) {
    return json(500, { error: e.message });
  }
};
