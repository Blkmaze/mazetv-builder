const { gh, checkPassword, json } = require("./_gh");

exports.handler = async (event) => {
  if (event.httpMethod !== "POST") return json(405, { error: "POST only" });
  try {
    const b = JSON.parse(event.body || "{}");
    checkPassword(b.password);

    const inputs = {
      app_name: (b.app_name || "").trim(),
      package_id: (b.package_id || "").trim().toLowerCase(),
      primary_color: (b.primary_color || "#E50914").trim(),
      portal_url: (b.portal_url || "").trim(),
      epg_url: (b.epg_url || "").trim(),
      vpn_url: (b.vpn_url || "").trim(),
      support_text: (b.support_text || "").trim(),
      icon_url: (b.icon_url || "").trim(),
      portals: (b.portals || "[]").trim(),
      pair_base_url: (b.pair_base_url || "").trim(),
    };
    if (!inputs.app_name) return json(400, { error: "App name is required" });
    if (!/^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$/.test(inputs.package_id))
      return json(400, { error: "Package id must look like com.yourbrand.tv (lowercase, dots, no spaces)" });
    if (!/^#[0-9a-fA-F]{6}$/.test(inputs.primary_color)) return json(400, { error: "Color must be #RRGGBB" });
    try { const parsed = JSON.parse(inputs.portals); if (!Array.isArray(parsed)) throw 0; } catch { return json(400, { error: "Pre-configured servers must be valid JSON list" }); }

    const since = new Date(Date.now() - 5000).toISOString();
    await gh(`/actions/workflows/build-apk.yml/dispatches`, {
      method: "POST",
      body: JSON.stringify({ ref: "main", inputs }),
    });
    return json(200, { ok: true, since });
  } catch (e) {
    return json(e.status || 500, { error: e.message });
  }
};
