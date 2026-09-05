const { gh, env, checkPassword, json } = require("./_gh");

async function bitly(longUrl, title) {
  const token = env("BITLY_TOKEN", false);
  if (!token) return null;
  try {
    const r = await fetch("https://api-ssl.bitly.com/v4/shorten", {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify({ long_url: longUrl, title }),
    });
    const j = await r.json();
    return j.link ? j.link.replace(/^https?:\/\//, "") : null;
  } catch { return null; }
}

exports.handler = async (event) => {
  try {
    const q = event.queryStringParameters || {};
    checkPassword(q.password);

    // Find the run that our dispatch started (workflow_dispatch gives no id back).
    let run = null;
    if (q.run_id) {
      run = await gh(`/actions/runs/${q.run_id}`);
    } else {
      const list = await gh(`/actions/workflows/build-apk.yml/runs?event=workflow_dispatch&created=>=${encodeURIComponent(q.since)}&per_page=5`);
      run = (list.workflow_runs || [])[0] || null;
      if (!run) return json(200, { state: "queued", message: "Waiting for GitHub to pick up the build…" });
    }

    const base = { run_id: run.id, run_number: run.run_number, url: run.html_url };
    if (run.status !== "completed") {
      return json(200, { ...base, state: "building", message: `Build #${run.run_number} is ${run.status.replace("_", " ")}…` });
    }
    if (run.conclusion !== "success") {
      return json(200, { ...base, state: "failed", message: `Build #${run.run_number} ${run.conclusion}. Open the log for details.` });
    }
    const rel = await gh(`/releases/tags/build-${run.run_number}`);
    const asset = (rel.assets || []).find((a) => a.name.endsWith(".apk"));
    if (!asset) return json(200, { ...base, state: "building", message: "Publishing the download…" });

    const download = asset.browser_download_url;
    const short = await bitly(download, asset.name);
    return json(200, { ...base, state: "done", download, short, size_mb: (asset.size / 1048576).toFixed(1) });
  } catch (e) {
    return json(e.status || 500, { error: e.message });
  }
};
