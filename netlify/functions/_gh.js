// Shared helpers for the builder functions. Secrets live in Netlify env vars:
//   GITHUB_TOKEN     fine-grained PAT: Actions (read/write) + Contents (read) on the builder repo
//   GITHUB_REPO      e.g. Blkmaze/mazetv-builder
//   BUILDER_PASSWORD password the dashboard asks for
//   BITLY_TOKEN      optional — if set, each build also gets a bit.ly code
const API = "https://api.github.com";

function env(name, required = true) {
  const v = process.env[name];
  if (required && !v) throw new Error(`Server is missing ${name}. Set it in Netlify → Site configuration → Environment variables.`);
  return v || "";
}

async function gh(path, opts = {}) {
  const r = await fetch(`${API}/repos/${env("GITHUB_REPO")}${path}`, {
    ...opts,
    headers: {
      Authorization: `Bearer ${env("GITHUB_TOKEN")}`,
      Accept: "application/vnd.github+json",
      "X-GitHub-Api-Version": "2022-11-28",
      "Content-Type": "application/json",
      ...(opts.headers || {}),
    },
  });
  if (r.status === 204) return null;
  const j = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(j.message || `GitHub ${r.status}`);
  return j;
}

function checkPassword(given) {
  if (given !== env("BUILDER_PASSWORD")) {
    const e = new Error("Wrong password"); e.status = 401; throw e;
  }
}

function json(status, body) {
  return { statusCode: status, headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) };
}

module.exports = { env, gh, checkPassword, json };
