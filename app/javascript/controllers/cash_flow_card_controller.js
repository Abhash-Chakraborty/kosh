import { Controller } from "@hotwired/stimulus";

// Home's cash flow chart. The section header's expand button shows only
// while there is a graph to expand, and the expanded view closes before
// Turbo caches the page.
export default class extends Controller {
  static targets = ["dialog"];

  connect() {
    this.#toggleExpand(false);
  }

  disconnect() {
    this.close();
  }

  update({ detail }) {
    this.#toggleExpand(detail.ready);
    if (!detail.ready) this.close();
  }

  close() {
    if (this.hasDialogTarget && this.dialogTarget.open)
      this.dialogTarget.close();
  }

  #toggleExpand(ready) {
    const button = this.element
      .closest("section")
      ?.querySelector("[data-action~='click->cashflow-expand#open']");
    if (button) button.hidden = !ready;
  }
}
