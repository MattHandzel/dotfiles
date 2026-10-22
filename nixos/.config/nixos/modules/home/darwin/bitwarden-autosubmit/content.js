// Bitwarden auto-submit: press the login button right after Bitwarden fills a
// login form, so a saved login needs no click at all (Oops 20261022-102326).
//
// Bitwarden's personal vault has no auto-submit: its own content/auto-submit-login.js
// only runs under the org policy AutomaticAppLogIn for an SSO IdP host. Its fill
// (insertValueIntoField) sets .value and dispatches synthetic keydown/keyup/input/
// change events. Synthetic events are visible here with isTrusted === false, while
// Matt typing, pasting or Espanso all produce trusted events. So: an untrusted input
// on a password field that now has a value = Bitwarden (or another filler) filled it.
//
// Guards: never on a form with 2+ visible password fields (sign-up / change
// password); never after Matt pressed a key or clicked after the fill; at most one
// auto-submit per origin per 60 s, so a wrong password cannot loop into a lockout.
// Username-only first steps (Google, Microsoft…) submit only when the form has a
// single visible text field that looks like a username, so card/identity fills
// (checkout forms) are never submitted.
(() => {
  const DELAY_MS = 350;
  const COOLDOWN_MS = 60000;
  const KEY = "__bw_autosubmit_last";
  let timer = null;
  let filledAt = 0;

  const visible = (el) => {
    if (!el || el.disabled || el.type === "hidden") return false;
    const r = el.getBoundingClientRect();
    if (r.width < 2 || r.height < 2) return false;
    const s = getComputedStyle(el);
    return s.visibility !== "hidden" && s.display !== "none" && s.opacity !== "0";
  };
  const textLike = (el) =>
    el.tagName === "INPUT" && ["text", "email", "tel", ""].includes((el.getAttribute("type") || "").toLowerCase());
  const usernameish = (el) =>
    /username|email/.test(el.autocomplete || "") ||
    el.type === "email" ||
    /user|login|email|ident|account/i.test(`${el.name} ${el.id}`);

  const scopeOf = (el) => el.form || el.closest("form") || el.getRootNode();
  const fields = (scope, sel) => [...scope.querySelectorAll(sel)].filter(visible);

  const SUBMIT_TEXT = /^\s*(log ?in|login|sign ?in|log on|logon|continue|next|submit|verify)\b/i;
  const findButton = (scope) => {
    const typed = fields(scope, 'button[type="submit"], input[type="submit"], input[type="image"]');
    if (typed.length) return typed[0];
    const all = fields(scope, 'button, [role="button"], input[type="button"], a');
    return all.find((b) => SUBMIT_TEXT.test(b.innerText || b.value || b.getAttribute("aria-label") || "")) || null;
  };

  const coolingDown = () => {
    try {
      return Date.now() - Number(sessionStorage.getItem(KEY) || 0) < COOLDOWN_MS;
    } catch (e) {
      return false;
    }
  };
  const stamp = () => {
    try {
      sessionStorage.setItem(KEY, String(Date.now()));
    } catch (e) {}
  };

  const submit = (field) => {
    timer = null;
    if (!field.isConnected || !field.value || coolingDown()) return;
    let scope = scopeOf(field);
    if (field.type === "password") {
      if (fields(scope, 'input[type="password"]').length > 1) return;
    } else {
      // Username-only step: no visible password field, exactly one text field, username-like.
      if (fields(scope, 'input[type="password"]').length) return;
      const texts = fields(scope, "input").filter(textLike);
      if (texts.length !== 1 || texts[0] !== field || !usernameish(field)) return;
    }
    let button = findButton(scope);
    // SPA logins often have no <form>: widen to the document once.
    if (!button && scope !== document) {
      scope = document;
      if (field.type === "password" && fields(scope, 'input[type="password"]').length > 1) return;
      button = findButton(scope);
    }
    stamp();
    if (button) button.click();
    else if (field.form) field.form.requestSubmit();
  };

  const onFill = (e) => {
    const el = e.target;
    if (e.isTrusted || !(el instanceof HTMLInputElement) || !el.value) return;
    const isPw = el.type === "password";
    if (!isPw && !(textLike(el) && usernameish(el))) return;
    // A password fill always wins over a pending username-only submit.
    if (timer && !isPw) return;
    clearTimeout(timer);
    filledAt = Date.now();
    timer = setTimeout(() => submit(el), DELAY_MS);
  };
  // Matt doing anything himself after the fill cancels the auto-submit.
  const onHuman = (e) => {
    if (e.isTrusted && timer && Date.now() - filledAt > 30) {
      clearTimeout(timer);
      timer = null;
    }
  };

  document.addEventListener("input", onFill, true);
  document.addEventListener("change", onFill, true);
  document.addEventListener("keydown", onHuman, true);
  document.addEventListener("mousedown", onHuman, true);
})();
