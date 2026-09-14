/* 말길 목업 공용 스크립트
   - 급수 상태(localStorage 'malgil.level') · ?demo=1 → Lv3
   - window.MALGIL (data.js, build_app_assets.py --mockup 산출) 로 지도·레벨 카드를 그림
   - Flutter 대응: AppState(level) · RegionRepo(assets) · ChoroplethPainter · LevelCard · RegionSheet */
(function () {
  const LV_ORDER = ['Lv1~2', 'Lv3', 'Lv4', 'Lv5'];
  const LV_NUM = { 'Lv1~2': 2, 'Lv3': 3, 'Lv4': 4, 'Lv5': 5 };
  const LV_LABEL = { 2: 'Lv1~2', 3: 'Lv3', 4: 'Lv4', 5: 'Lv5' };
  const TOPIK = { 2: 'TOPIK 1–2 or none', 3: 'TOPIK 3', 4: 'TOPIK 4', 5: 'TOPIK 5–6' };

  const M = window.MALGIL || null;
  const q = new URLSearchParams(location.search);

  function getLevel() {
    if (q.get('demo') === '1') { setLevel(3); return 3; }
    try { const v = parseInt(localStorage.getItem('malgil.level') || '', 10); if (v >= 2 && v <= 5) return v; } catch (e) {}
    return null;
  }
  function setLevel(n) { try { localStorage.setItem('malgil.level', String(n)); } catch (e) {} }

  /* 지역 급수 → 화면 상태 */
  function stateOf(row, userLv) {
    const lv = row.lv;
    if (lv === '보류') return 'hold';
    if (lv === '제외') return 'excluded';
    if (lv === 'Lv1~2') return 'lv12';
    const n = LV_NUM[lv];
    if (!n) return 'excluded';
    return n <= userLv ? ('lv' + n) : 'locked';
  }
  function isOpen(row, userLv) { const s = stateOf(row, userLv); return s === 'lv12' || /^lv[345]$/.test(s); }

  /* 기초지자체 단위 행(일반구는 parent로 접음) */
  function baseRows() {
    if (!M) return [];
    return M.데이터.지역.filter(r => !r.parent || r.parent === r.code);
  }
  function summary(userLv) {
    const rows = baseRows();
    const countable = rows.filter(r => r.lv !== '보류' && r.lv !== '제외');
    const open = countable.filter(r => isOpen(r, userLv));
    const r89 = rows.filter(r => r.is89);
    const open89 = r89.filter(r => isOpen(r, userLv));
    const next = userLv < 5 ? countable.filter(r => LV_NUM[r.lv] === userLv + 1) : [];
    return { total: countable.length, open: open.length, total89: r89.length, open89: open89.length,
             next, nextLv: userLv < 5 ? userLv + 1 : null };
  }

  /* 지도 렌더 */
  function renderMap(svg, userLv, opts) {
    opts = opts || {};
    if (!M) { svg.outerHTML = '<div class="pad body-medium muted">data.js not built yet — run <span class="kbd">python data/AI/build_app_assets.py --mockup</span></div>'; return; }
    const vb = (M.데이터.메타 && M.데이터.메타.viewBox) || '0 0 1000 1300';
    svg.setAttribute('viewBox', vb);
    const byCode = {}; M.데이터.지역.forEach(r => byCode[r.code] = r);
    const bounds = M.데이터.경계;
    let html = '<defs><pattern id="hatch" patternUnits="userSpaceOnUse" width="6" height="6" patternTransform="rotate(45)"><rect width="6" height="6" fill="#ffffff"/><line x1="0" y1="0" x2="0" y2="6" stroke="#898781" stroke-width="1.2"/></pattern></defs>';
    Object.keys(bounds).forEach(code => {
      const row = byCode[code]; if (!row) return;
      const src = (row.parent && row.parent !== code && byCode[row.parent]) ? byCode[row.parent] : row;
      const st = stateOf(src, userLv);
      const d = bounds[code].map(ring => 'M' + ring.map(p => p[0] + ' ' + p[1]).join('L') + 'Z').join('');
      const cls = [st, src.is89 && opts.show89 !== false ? 'is89' : '', opts.selected === src.code ? 'selected' : ''].join(' ').trim();
      html += `<path d="${d}" class="${cls}" data-code="${src.code}"><title>${src.sido} ${src.nm} · ${src.lv}</title></path>`;
    });
    svg.innerHTML = html;
    svg.onclick = e => { const p = e.target.closest('path'); if (p && opts.onSelect) opts.onSelect(byCode[p.dataset.code]); };
  }

  /* 근거 문장 (절대값만 — P-T01·02) */
  function whyText(row) {
    if (row.근거_en) return row.근거_en;
    const parts = [];
    if (row.share != null) parts.push(`Foreign visitors ${Math.max(1, Math.round(row.share * 10))} in 1,000`);
    if (row.구분) parts.push({ '자치구': 'Metropolitan district', '시': 'City', '군': 'County' }[row.구분] || row.구분);
    if (row.e65 != null) parts.push(`Residents 65+: ${Math.round(row.e65 / 10)} in 10`);
    if (row.kor != null) parts.push(`${row.kor} places listed`);
    return parts.join(' · ');
  }
  function lockedText(row) { return `Opens at ${row.lv} — you can still visit; expect Korean for transport and ordering`; }

  /* 지역 시트 */
  function fillSheet(el, row, userLv) {
    const st = stateOf(row, userLv);
    const lvClass = { lv12: 'lv12', lv3: 'lv3', lv4: 'lv4', lv5: 'lv5', locked: LV_NUM[row.lv] ? 'lv' + LV_NUM[row.lv] : 'lv', hold: 'hold', excluded: 'excluded' }[st];
    const lvText = { lv12: 'Any level', hold: 'On hold', excluded: 'Not enough data' }[st] || row.lv;
    const meta = (M && M.데이터.메타) || {};
    el.innerHTML = `
      <div class="handle"></div>
      <div class="row">
        <div>
          <div class="title-large ko">${row.nm}</div>
          <div class="body-medium muted ko">${row.sido}</div>
        </div>
        <div class="spacer"></div>
        <span class="lv ${lvClass}" data-flutter="Chip">${lvText}</span>
        ${row.is89 ? '<span class="badge-89" title="행정안전부 인구감소지역">Depopulation area</span>' : ''}
      </div>
      <div class="divider"></div>
      <div class="body-medium">${whyText(row)}</div>
      <div class="body-small muted" style="margin-top:4px">Computed ${meta.산출일 || '2026-09-14'} · 출처: ⓒ한국관광공사 · 행정안전부 주민등록 인구</div>
      ${st === 'locked' ? `<div class="banner" style="margin:12px -16px 0;border-radius:0">🔒 <div class="body-medium">${lockedText(row)}</div></div>` : ''}
      ${st === 'hold' ? `<div class="body-medium muted" style="margin-top:12px">Reorganized on 2026-07-01 — only ${row.months || 1} month of visitor data. Level pending.</div>` : ''}
      ${st === 'excluded' ? `<div class="body-medium muted" style="margin-top:12px">Fewer than 20 listed places — not enough to draw a map.</div>` : ''}
      <div class="stack" style="margin-top:16px">
        <a class="btn filled block" data-flutter="FilledButton" href="03_places.html?code=${row.code}&name=${encodeURIComponent(row.nm)}&lv=${encodeURIComponent(row.lv)}">Places · live</a>
        <div class="card outlined" data-flutter="Card.outlined">
          <div class="title-small">Local companion</div>
          <div class="body-medium muted" style="margin-top:4px">Recruiting in this area. Until then, book a licensed cultural tourism interpreter.</div>
          <a class="btn text" data-flutter="TextButton.icon" href="https://www.kctg.or.kr" target="_blank" rel="noopener">Open kctg.or.kr ↗</a>
        </div>
        <label class="check body-medium" data-flutter="CheckboxListTile"><input type="checkbox"> I stayed here today (self-reported)</label>
        <div class="body-small muted">생활인구로 산정되는 것과 같은 형태의 체류입니다. <br>본 지표는 행정안전부 생활인구 산정 결과가 아니며, 사용자가 스스로 확인하도록 만든 자체 지표입니다.</div>
      </div>`;
  }

  /* 목업 툴바(데스크톱 폭 토글·급수) */
  function toolbar() {
    const t = document.createElement('div'); t.className = 'mock-toolbar';
    t.innerHTML = '<button id="tb-width">Desktop width</button>';
    document.body.appendChild(t);
    t.querySelector('#tb-width').onclick = () => { document.body.classList.toggle('desktop'); };
  }

  window.MK = { LV_ORDER, LV_NUM, LV_LABEL, TOPIK, M, getLevel, setLevel, stateOf, isOpen, summary, renderMap, whyText, lockedText, fillSheet, toolbar, baseRows };
})();
