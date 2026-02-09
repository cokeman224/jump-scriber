let Hooks = {}

Hooks.AskSidebarOpener = {
    mounted() {
        this._openHandler = () => this.pushEvent("open", {})
        window.addEventListener("open-ask-sidebar", this._openHandler)
    },
    destroyed() {
        window.removeEventListener("open-ask-sidebar", this._openHandler)
    }
}

Hooks.ScrollToBottom = {
    mounted() {
        this.handleEvent("scroll_ask_to_bottom", () => this.scrollToBottom())
        this.scrollToBottom()
    },
    scrollToBottom() {
        this.el.scrollTop = this.el.scrollHeight
    }
}

Hooks.EnterToSubmit = {
    mounted() {
        this._keydown = (e) => {
            if (e.key === "Enter" && !e.shiftKey) {
                e.preventDefault()
                this.el.closest("form")?.requestSubmit()
            }
        }
        this.el.addEventListener("keydown", this._keydown)
    },
    destroyed() {
        this.el.removeEventListener("keydown", this._keydown)
    }
}

Hooks.FocusAskInput = {
    mounted() {
        this.handleEvent("focus_ask_input", () => {
            this.el.querySelector("#ask-message-input")?.focus()
        })
    }
}

Hooks.Clipboard = {
    mounted() {
        this.handleEvent("copy-to-clipboard", ({ text: text }) => {
            navigator.clipboard.writeText(text).then(() => {
                this.pushEventTo(this.el, "copied-to-clipboard", { text: text })
                setTimeout(() => {
                    this.pushEventTo(this.el, "reset-copied", {})
                }, 2000)
            })
        })
    }
}

export default Hooks