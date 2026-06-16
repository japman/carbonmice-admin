import { Controller } from "@hotwired/stimulus"

// Debounced auto-submit of a GET filter form. The visible submit button still
// works without JS.
export default class extends Controller {
  static values = { delay: { type: Number, default: 300 } }

  disconnect() {
    clearTimeout(this.timer)
  }

  submit() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.element.requestSubmit(), this.delayValue)
  }

  submitNow() {
    clearTimeout(this.timer)
    this.element.requestSubmit()
  }
}
