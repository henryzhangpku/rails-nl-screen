import { Controller } from "@hotwired/stimulus"

// Submits the history filter form. The form itself targets the "screens" Turbo Frame and
// advances the URL; this controller only decides *when*: at once for selects and checkboxes,
// after a short pause while typing.
export default class extends Controller {
  submit() {
    clearTimeout(this.timeout)
    this.element.requestSubmit()
  }

  submitLater() {
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => this.element.requestSubmit(), 300)
  }

  disconnect() {
    clearTimeout(this.timeout)
  }
}
