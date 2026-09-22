import { Controller } from "@hotwired/stimulus"

// Leaves the address bar reading the site root. It takes out any utm keys and
// replaces a path such as /k3 or /rsvp with /. The server already holds the
// values, in the hidden fields of the RSVP form, so the URL does not need to
// carry them and a shared or bookmarked link stays clean.
//
// Any other query parameter and the fragment are left alone. Nothing is
// stored on the device. See UtmCapture and D-029.
export default class extends Controller {
  connect() {
    const url = new URL(location.href)
    const keys = [...url.searchParams.keys()].filter((k) => k.startsWith("utm_"))
    if (keys.length === 0 && url.pathname === "/") return

    keys.forEach((k) => url.searchParams.delete(k))
    history.replaceState(history.state, "", "/" + url.search + url.hash)
  }
}
