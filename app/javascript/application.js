// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import { Turbo } from "@hotwired/turbo-rails"
import "controllers"

// Replace the native confirm() used by data-turbo-confirm with a styled dialog.
Turbo.setConfirmMethod((message) => {
  return new Promise((resolve) => {
    const overlay = document.createElement("div")
    overlay.className = "fixed inset-0 z-50 flex items-center justify-center bg-black/40"
    overlay.innerHTML = `
      <div class="w-full max-w-sm rounded-xl bg-white p-6 shadow-lg">
        <p data-confirm-message class="text-ink"></p>
        <div class="mt-5 flex justify-end gap-3">
          <button data-confirm-cancel class="rounded-lg px-4 py-2 font-semibold text-body hover:bg-surface cursor-pointer">ยกเลิก</button>
          <button data-confirm-ok class="rounded-lg bg-danger px-4 py-2 font-semibold text-white hover:bg-danger-dark cursor-pointer">ยืนยัน</button>
        </div>
      </div>`
    overlay.querySelector("[data-confirm-message]").textContent = message
    const cleanup = (result) => { overlay.remove(); document.removeEventListener("keydown", onKey); resolve(result) }
    const onKey = (e) => { if (e.key === "Escape") cleanup(false) }
    overlay.addEventListener("click", (e) => { if (e.target === overlay) cleanup(false) })
    overlay.querySelector("[data-confirm-cancel]").addEventListener("click", () => cleanup(false))
    overlay.querySelector("[data-confirm-ok]").addEventListener("click", () => cleanup(true))
    document.addEventListener("keydown", onKey)
    document.body.appendChild(overlay)
    overlay.querySelector("[data-confirm-ok]").focus()
  })
})
