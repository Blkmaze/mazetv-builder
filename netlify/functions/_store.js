// Shared Netlify Blobs store for the TV pairing flow.
//
// getStore("mazetv-pairing") alone relies on Netlify auto-injecting the
// site/token context at runtime. That auto-injection isn't available on
// this account, so we configure it explicitly using BLOBS_SITE_ID /
// BLOBS_TOKEN (site environment variables) instead.
const { getStore } = require("@netlify/blobs");

function pairingStore() {
  return getStore({
    name: "mazetv-pairing",
    siteID: process.env.BLOBS_SITE_ID,
    token: process.env.BLOBS_TOKEN,
  });
}

module.exports = { pairingStore };
