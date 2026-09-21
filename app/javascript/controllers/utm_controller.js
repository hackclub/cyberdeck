import { Controller } from "@hotwired/stimulus"

// Takes the utm keys out of the address bar. The server has already put them
// in a signed cookie by the time this runs, so the URL does not need to carry
// them and a shared or bookmarked link stays clean. Any other query parameter
// and the fragment are left alone. See UtmCapture.
export default class extends Controller {
  connect() {
    const url = new URL(location.href)
    const keys = [...url.searchParams.keys()].filter((k) => k.startsWith("utm_"))
    if (keys.length === 0) return

    keys.forEach((k) => url.searchParams.delete(k))
    history.replaceState(history.state, "", url.pathname + url.search + url.hash)
  }
}
