import { Controller } from "@hotwired/stimulus"

// Connected on the overlay element rendered inside <turbo-frame id="modal">.
// Closing empties the frame, which removes this element and triggers disconnect().
export default class extends Controller {
  connect() {
    document.body.classList.add("overflow-hidden")
    this.onKeydown = (e) => { if (e.key === "Escape") this.close() }
    document.addEventListener("keydown", this.onKeydown)
  }

  disconnect() {
    document.body.classList.remove("overflow-hidden")
    document.removeEventListener("keydown", this.onKeydown)
  }

  backdrop(event) {
    if (event.target === this.element) this.close()
  }

  close() {
    const frame = document.getElementById("modal")
    if (frame) frame.innerHTML = ""
  }
}
