(function () {
  "use strict";

  const MIN_LENGTH = 12;
  const MAX_BYTES = 72;
  const FORM_IDS = ["registerForm", "registrationForm", "guestForm", "passwordForm", "newPasswordForm"];

  function countCharacters(value) { return Array.from(value).length; }
  function countUtf8Bytes(value) { return new TextEncoder().encode(value).length; }

  function getStatusNode(form, passwordInput) {
    let status = form.querySelector("[data-ft-password-status]");
    if (!status) {
      status = document.createElement("p");
      status.setAttribute("data-ft-password-status", "");
      status.id = "ft-password-status-" + (form.id || "form");
      status.setAttribute("role", "status");
      status.setAttribute("aria-live", "polite");
      status.style.cssText = "margin:7px 0 12px;color:#526579;font-size:12px;line-height:1.5";
      const adjacentNote = passwordInput.nextElementSibling && passwordInput.nextElementSibling.tagName === "P" ? passwordInput.nextElementSibling : null;
      const anchor = passwordInput.closest(".field, .form-group");
      if (adjacentNote) adjacentNote.insertAdjacentElement("afterend", status);
      else if (anchor) anchor.insertAdjacentElement("afterend", status);
      else passwordInput.insertAdjacentElement("afterend", status);
    }
    return status;
  }

  function validate(passwordInput, confirmInput, status, showErrors) {
    const password = passwordInput.value;
    const length = countCharacters(password);
    const bytes = countUtf8Bytes(password);
    let message = "";
    if (showErrors && password.length > 0 && !password.trim()) message = "Your password cannot contain only spaces.";
    else if (showErrors && password.length > 0 && length < MIN_LENGTH) message = "Use at least 12 characters. A memorable passphrase is a good choice.";
    else if (showErrors && bytes > MAX_BYTES) message = "Your password must not exceed 72 UTF-8 bytes. Use fewer characters or simpler characters.";
    else if (showErrors && confirmInput && confirmInput.value && password !== confirmInput.value) message = "The passwords do not match.";

    passwordInput.setCustomValidity(message && password.length > 0 ? message : "");
    if (confirmInput) confirmInput.setCustomValidity(showErrors && confirmInput.value && password !== confirmInput.value ? "The passwords do not match." : "");
    if (status) {
      status.textContent = message || (password.length === 0 ? "Password guidance: 12 or more characters, up to 72 UTF-8 bytes. Spaces and passphrases are allowed." : "Password length looks good. Avoid reusing a password from another service.");
      status.style.color = message ? "#a11919" : "#526579";
    }
    return !message;
  }

  function attach(form) {
    const passwordInput = form.querySelector('input[type="password"][autocomplete="new-password"], input[type="password"]');
    if (!passwordInput) return;
    const confirmInput = form.querySelector('input[id*="confirm" i], input[name*="confirm" i]');
    passwordInput.minLength = MIN_LENGTH;
    // Do not set maxLength: it silently truncates input before the 72-byte validator can explain the error.
    if (confirmInput) confirmInput.minLength = MIN_LENGTH;
    const statusId = "ft-password-status-" + (form.id || "form");
    const describedBy = (passwordInput.getAttribute("aria-describedby") || "").trim().split(/\s+/).filter(Boolean);
    if (!describedBy.includes(statusId)) describedBy.push(statusId);
    passwordInput.setAttribute("aria-describedby", describedBy.join(" "));
    const status = getStatusNode(form, passwordInput);
    const update = (showErrors) => validate(passwordInput, confirmInput, status, showErrors);
    passwordInput.addEventListener("input", () => update(true));
    if (confirmInput) confirmInput.addEventListener("input", () => update(true));
    form.addEventListener("submit", function (event) {
      if (!update(true)) {
        event.preventDefault();
        event.stopImmediatePropagation();
        if (!passwordInput.validity.valid) passwordInput.reportValidity();
        if (confirmInput && !confirmInput.validity.valid) confirmInput.reportValidity();
      }
    }, true);
    update(false);
  }

  function initializePasswordPolicy() {
    FORM_IDS.forEach(function (id) { const form = document.getElementById(id); if (form) attach(form); });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", initializePasswordPolicy, { once: true });
  } else {
    initializePasswordPolicy();
  }
})();