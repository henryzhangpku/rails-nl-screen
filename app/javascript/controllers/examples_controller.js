import { Controller } from "@hotwired/stimulus"

// Clicking an example fills the query box: <button data-action="examples#fill" data-examples-query-param="...">
export default class extends Controller {
  static targets = ["input"]

  fill({ params: { query } }) {
    this.inputTarget.value = query
    this.inputTarget.focus()
  }
}
