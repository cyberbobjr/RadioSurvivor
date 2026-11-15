// Tiny DOM helpers of the page: h(tag, attributes, ...children). `on<Event>` attributes become listeners, `class`
// and `text` are shortcuts, false/null children are skipped.

export function h(tag, attrs = {}, ...children) {
  const el = document.createElement(tag);
  for (const [name, val] of Object.entries(attrs ?? {})) {
    if (val === undefined || val === null || val === false) continue;
    if (name.startsWith('on') && typeof val === 'function') el.addEventListener(name.slice(2).toLowerCase(), val);
    else if (name === 'class') el.className = val;
    else if (name === 'text') el.textContent = val;
    else if (name === 'value') el.value = val;
    else if (name === 'checked' || name === 'disabled' || name === 'open' || name === 'selected') el[name] = Boolean(val);
    else el.setAttribute(name, val === true ? '' : String(val));
  }
  append(el, children);
  return el;
}

export function append(el, children) {
  for (const child of children.flat(Infinity)) {
    if (child === null || child === undefined || child === false) continue;
    el.append(child instanceof Node ? child : document.createTextNode(String(child)));
  }
  return el;
}

export function clear(el) {
  el.replaceChildren();
  return el;
}

let counter = 0;
export function uid(prefix = 'f') {
  counter += 1;
  return `${prefix}${counter}`;
}

// A select of [{value, label}] with the current value kept even when it is not offered (shown as is).
export function select(options, current, onChange, attrs = {}) {
  const list = [...options];
  if (current && !list.some((o) => o.value === current)) list.push({ value: current, label: current });
  return h('select', { ...attrs, onChange: (e) => onChange(e.target.value) },
    list.map((o) => h('option', { value: o.value, selected: o.value === current, text: o.label })));
}
