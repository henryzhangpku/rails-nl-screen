import { Controller } from "@hotwired/stimulus"

// A toast that dismisses itself after a few seconds, or on click.
export default class extends Controller {
  connect() {
    this.timeout = setTimeout(() => this.dismiss(), 4000)
  }

  disconnect() {
    clearTimeout(this.timeout)
  }

  dismiss() {
    this.element.remove()
  }
}
