import { Controller } from "@hotwired/stimulus"

// Fills the RSVP box from Hack Club Auth without a login. If the visitor has
// a session at auth.hackclub.com, its whoami endpoint returns their email.
// Two conditions, both outside this file: cyberdeck.hackclub.com must be set
// as the HCA app's whoami_allowed_origin by an Auth admin, and the page must
// be served under hackclub.com so the SameSite=Lax cookie travels. Anywhere
// else the fetch fails or says signed_in: false, and the box stays empty.
// Pattern from hackclub/jamegam, src/lib/prefill.js. Armand, 2026-09-21:
// "I want prefill". See wiki/decisions/D-023-rsvp-to-airtable-fillout-prefill.md.
const WHOAMI = "https://auth.hackclub.com/api/external/whoami"

// One request per page load, shared by every box on the page.
let lookup = null
function whoami() {
  lookup ||= fetch(WHOAMI, { credentials: "include", headers: { Accept: "application/json" } })
    .then((response) => (response.ok ? response.json() : null))
    .then((data) => (data && data.signed_in && data.email ? data.email : ""))
    .catch(() => "")
  return lookup
}

export default class extends Controller {
  static targets = ["email"]

  async connect() {
    const email = await whoami()
    if (!email) return
    // Never write over something the visitor already typed.
    this.emailTargets.forEach((input) => { if (!input.value) input.value = email })
  }
}
