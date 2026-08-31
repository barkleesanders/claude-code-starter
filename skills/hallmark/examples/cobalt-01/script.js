/* Distil · Cobalt theme — composed, minimal motion.
 * 1) IntersectionObserver reveals (fade + ~10px rise), per-section stagger via --i.
 * 2) The hero response types ONE line in once (~600ms), then static.
 * 3) Nav gains a stronger hairline on scroll.
 * 4) Install line copy affordance.
 * All animation is bypassed under prefers-reduced-motion. */
(function () {
  'use strict';

  var reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  /* ─── Nav scroll-frost ─── */
  var nav = document.getElementById('nav');
  if (nav) {
    var ticking = false;
    function onScroll() { nav.classList.toggle('is-scrolled', window.scrollY > 16); ticking = false; }
    window.addEventListener('scroll', function () {
      if (!ticking) { requestAnimationFrame(onScroll); ticking = true; }
    }, { passive: true });
    onScroll();
  }

  /* ─── Copy install command ─── */
  var copyBtn = document.querySelector('.strip__copy');
  if (copyBtn && navigator.clipboard) {
    copyBtn.addEventListener('click', function () {
      navigator.clipboard.writeText('npm i @distil/sdk').then(function () {
        copyBtn.textContent = 'Copied';
        copyBtn.classList.add('is-copied');
        setTimeout(function () {
          copyBtn.textContent = 'Copy';
          copyBtn.classList.remove('is-copied');
        }, 1600);
      }).catch(function () {});
    });
  }

  /* ─── Reduced motion / no IO: reveal everything, fill the typed line ─── */
  function fillTyped() {
    var typed = document.querySelector('.type');
    if (typed && typed.dataset.type) typed.textContent = typed.dataset.type;
  }

  if (reduced || !('IntersectionObserver' in window)) {
    document.querySelectorAll('.reveal').forEach(function (el) { el.classList.add('is-inview'); });
    fillTyped();
    return;
  }

  /* ─── Section-grouped reveals ─── */
  var sections = document.querySelectorAll('main > section, .foot');
  var io = new IntersectionObserver(function (entries, obs) {
    entries.forEach(function (entry) {
      if (!entry.isIntersecting) return;
      entry.target.querySelectorAll('.reveal').forEach(function (el) { el.classList.add('is-inview'); });
      obs.unobserve(entry.target);
    });
  }, { rootMargin: '0px 0px -10% 0px', threshold: 0.08 });
  sections.forEach(function (s) { if (s.querySelector('.reveal')) io.observe(s); });

  /* ─── Hero: type ONE response line in once, then static ─── */
  var typed = document.querySelector('.type');
  var cursor = document.querySelector('.c-cursor');
  if (typed && typed.dataset.type) {
    var full = typed.dataset.type;
    var heroDemo = document.querySelector('.demo');

    function runType() {
      if (cursor) cursor.classList.add('is-blinking');
      var i = 0;
      var total = 600;                                  // ~600ms total
      var stepMs = Math.max(12, Math.round(total / full.length));
      var timer = setInterval(function () {
        i += 1;
        typed.textContent = full.slice(0, i);
        if (i >= full.length) { clearInterval(timer); }
      }, stepMs);
    }

    var startObs = new IntersectionObserver(function (entries, obs) {
      entries.forEach(function (e) {
        if (!e.isIntersecting) return;
        setTimeout(runType, 380);                       // begin after the reveal settles
        obs.disconnect();
      });
    }, { threshold: 0.4 });

    if (heroDemo) startObs.observe(heroDemo); else runType();
  }
})();

/* ─── Command palette · ⌘K / Ctrl+K · Cobalt's signature interactive feature ─── */
(function () {
  'use strict';

  var palette = document.getElementById('palette');
  var trigger = document.getElementById('cmdk-trigger');
  var input = document.getElementById('palette-input');
  var list = document.getElementById('palette-list');
  if (!palette || !trigger || !input || !list) return;

  var backdrop = palette.querySelector('[data-palette-close]');
  var rows = Array.prototype.slice.call(list.querySelectorAll('.palette__row'));
  var selected = 0;
  var lastFocus = null;

  /* targets each command jumps to (in-page anchors / actions) */
  var actions = {
    quickstart: function () { go('#docs'); },
    api:        function () { go('#docs'); },
    pricing:    function () { go('#pricing'); },
    key:        function () { go('#pricing'); },
    copy:       function () {
      if (navigator.clipboard) { navigator.clipboard.writeText('npm i @distil/sdk').catch(function () {}); }
      var btn = document.querySelector('.strip__copy');
      if (btn) { btn.textContent = 'Copied'; btn.classList.add('is-copied'); }
    }
  };

  function go(hash) {
    var el = document.querySelector(hash);
    close();
    if (el && el.scrollIntoView) { el.scrollIntoView({ behavior: 'smooth', block: 'start' }); }
    else { window.location.hash = hash; }
  }

  function visibleRows() {
    return rows.filter(function (r) { return !r.hidden; });
  }

  function setSelected(idx) {
    var vis = visibleRows();
    if (!vis.length) { selected = -1; input.removeAttribute('aria-activedescendant'); return; }
    if (idx < 0) idx = vis.length - 1;
    if (idx >= vis.length) idx = 0;
    selected = idx;
    rows.forEach(function (r) { r.setAttribute('aria-selected', 'false'); });
    var cur = vis[selected];
    cur.setAttribute('aria-selected', 'true');
    input.setAttribute('aria-activedescendant', cur.id);
    cur.scrollIntoView({ block: 'nearest' });
  }

  function filter(q) {
    q = q.trim().toLowerCase();
    rows.forEach(function (r) {
      var text = r.textContent.toLowerCase();
      r.hidden = q !== '' && text.indexOf(q) === -1;
    });
    setSelected(0);
  }

  function isOpen() { return !palette.hidden; }

  function open() {
    if (isOpen()) return;
    lastFocus = document.activeElement;
    palette.hidden = false;
    trigger.setAttribute('aria-expanded', 'true');
    input.value = '';
    filter('');
    setSelected(0);
    /* move focus into the input on open */
    input.focus();
  }

  function close() {
    if (!isOpen()) return;
    palette.hidden = true;
    trigger.setAttribute('aria-expanded', 'false');
    /* return focus to the trigger on close (or whatever real control opened it) */
    var dest = (lastFocus && lastFocus.focus && lastFocus !== document.body) ? lastFocus : trigger;
    dest.focus();
  }

  function toggle() { isOpen() ? close() : open(); }

  function activate() {
    var vis = visibleRows();
    if (selected < 0 || !vis[selected]) return;
    var cmd = vis[selected].getAttribute('data-cmd');
    if (actions[cmd]) actions[cmd]();
    else close();
  }

  /* trigger click */
  trigger.addEventListener('click', open);

  /* backdrop click closes */
  if (backdrop) backdrop.addEventListener('click', close);

  /* global ⌘K / Ctrl+K toggles */
  document.addEventListener('keydown', function (e) {
    if ((e.metaKey || e.ctrlKey) && (e.key === 'k' || e.key === 'K')) {
      e.preventDefault();
      toggle();
    }
  });

  /* within the palette: Esc, arrows, Enter */
  palette.addEventListener('keydown', function (e) {
    if (e.key === 'Escape') { e.preventDefault(); close(); return; }
    if (e.key === 'ArrowDown') { e.preventDefault(); setSelected(selected + 1); return; }
    if (e.key === 'ArrowUp') { e.preventDefault(); setSelected(selected - 1); return; }
    if (e.key === 'Enter') { e.preventDefault(); activate(); return; }
  });

  /* type to filter */
  input.addEventListener('input', function () { filter(input.value); });

  /* pointer over a row selects it; click activates */
  rows.forEach(function (row) {
    row.addEventListener('mousemove', function () {
      var vis = visibleRows();
      var i = vis.indexOf(row);
      if (i !== -1 && i !== selected) setSelected(i);
    });
    row.addEventListener('click', function () {
      var vis = visibleRows();
      var i = vis.indexOf(row);
      if (i !== -1) { selected = i; }
      activate();
    });
  });
})();
