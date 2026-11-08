const state = {
  user: null,
  questions: [],
  safetyQuestions: [],
  checks: [],
  users: [],
  visibleChecks: [],
  canAssignRoles: false,
  lastCheck: null,
};

const byId = (id) => document.getElementById(id);
const escapeHtml = (value) => String(value ?? '').replace(/[&<>"']/g, (char) => ({
  '&': '&amp;',
  '<': '&lt;',
  '>': '&gt;',
  '"': '&quot;',
  "'": '&#39;',
}[char]));

async function api(path, options = {}) {
  const response = await fetch(path, {
    credentials: 'same-origin',
    headers: options.body ? { 'Content-Type': 'application/json' } : {},
    ...options,
  });
  let result;
  try {
    result = await response.json();
  } catch {
    throw new Error('O servidor retornou uma resposta inválida. Tente novamente.');
  }
  if (!response.ok) {
    throw new Error(result.error || 'Não foi possível concluir a solicitação.');
  }
  return result;
}

function showNotice(id, message) {
  const element = byId(id);
  element.textContent = message;
  element.hidden = false;
}

function hideNotice(id) {
  byId(id).hidden = true;
}

function showHistoryNotice(message, type = 'error') {
  const notice = byId('history-alert');
  notice.classList.toggle('error', type === 'error');
  notice.classList.toggle('success', type === 'success');
  showNotice('history-alert', message);
}

function setView(viewId) {
  document.querySelectorAll('.content-panel').forEach((panel) => {
    panel.hidden = panel.id !== viewId;
  });
  document.querySelectorAll('.tab').forEach((tab) => {
    tab.classList.toggle('active', tab.dataset.view === viewId);
  });
  if (viewId === 'history-panel') loadHistory();
  if (viewId === 'users-panel') loadUsers();
  window.scrollTo({ top: 0, behavior: 'smooth' });
}

function renderQuestions() {
  byId('questions').innerHTML = state.questions.map((question) => `
    <fieldset class="check-item">
      <legend>
        <span class="question-text">
          <span class="question-number">${String(question.id).padStart(2, '0')}</span>
          <span>${escapeHtml(question.text)} <span class="required-mark" aria-label="obrigatório">*</span></span>
        </span>
      </legend>
      <div class="choices" role="radiogroup" aria-label="${escapeHtml(question.text)}">
        <label class="choice"><input type="radio" name="answer-${question.id}" value="ok" required><span>Conforme</span></label>
        <label class="choice problem"><input type="radio" name="answer-${question.id}" value="problem" required><span>Não conforme</span></label>
        <label class="choice"><input type="radio" name="answer-${question.id}" value="na" required><span>Não se aplica</span></label>
      </div>
    </fieldset>
  `).join('');
  byId('safety-questions').innerHTML = state.safetyQuestions.map((question, index) => `
    <fieldset class="check-item safety-item">
      <legend>
        <span class="question-text">
          <span class="question-number">${String(index + 1).padStart(2, '0')}</span>
          <span>${escapeHtml(question.text)} <span class="required-mark" aria-label="obrigatório">*</span></span>
        </span>
      </legend>
      <div class="choices" role="radiogroup" aria-label="${escapeHtml(question.text)}">
        <label class="choice"><input type="radio" name="safety-${escapeHtml(question.id)}" value="ok" required><span>Conforme</span></label>
        <label class="choice problem"><input type="radio" name="safety-${escapeHtml(question.id)}" value="problem" required><span>Não conforme</span></label>
      </div>
    </fieldset>
  `).join('');
}

function renderApp() {
  byId('login-view').hidden = true;
  byId('password-view').hidden = true;
  byId('app-view').hidden = false;
  byId('welcome-title').textContent = `Olá, ${state.user.displayName}`;
  byId('welcome-caption').textContent = state.user.role === 'admin'
    ? 'Acompanhe os horários e os resultados das inspeções.'
    : 'Preencha uma inspeção antes de cada uso da empilhadeira.';
  byId('history-title').textContent = state.user.role === 'admin' ? 'Inspeções registradas' : 'Meu histórico';
  byId('users-tab').hidden = state.user.role !== 'admin';
  byId('history-filters').hidden = state.user.role !== 'admin';
  byId('checklist-panel').hidden = state.user.role === 'admin';
  byId('history-panel').hidden = state.user.role !== 'admin';
  byId('users-panel').hidden = true;
  document.querySelectorAll('.tab').forEach((tab) => {
    tab.classList.toggle('active', tab.dataset.view === (state.user.role === 'admin' ? 'history-panel' : 'checklist-panel'));
  });
  if (state.user.role === 'operator') {
    renderQuestions();
  } else {
    loadHistory();
  }
}

function formatDate(value) {
  return new Intl.DateTimeFormat('pt-BR', {
    dateStyle: 'short',
    timeStyle: 'medium',
  }).format(new Date(value));
}

function pdfTextHex(value) {
  const windows1252 = new Map([
    [0x20ac, 0x80], [0x201a, 0x82], [0x192, 0x83], [0x201e, 0x84], [0x2026, 0x85],
    [0x2020, 0x86], [0x2021, 0x87], [0x2c6, 0x88], [0x2030, 0x89], [0x160, 0x8a],
    [0x2039, 0x8b], [0x152, 0x8c], [0x17d, 0x8e], [0x2018, 0x91], [0x2019, 0x92],
    [0x201c, 0x93], [0x201d, 0x94], [0x2022, 0x95], [0x2013, 0x96], [0x2014, 0x97],
    [0x2dc, 0x98], [0x2122, 0x99], [0x161, 0x9a], [0x203a, 0x9b], [0x153, 0x9c],
    [0x17e, 0x9e], [0x178, 0x9f],
  ]);
  return Array.from(String(value), (character) => {
    const code = character.codePointAt(0);
    const byte = code <= 0xff ? code : windows1252.get(code) ?? 0x3f;
    return byte.toString(16).padStart(2, '0');
  }).join('').toUpperCase();
}

function wrapPdfText(value, maxCharacters) {
  const words = String(value).split(/\s+/);
  const lines = [];
  let line = '';
  words.forEach((originalWord) => {
    let word = originalWord;
    if (line && `${line} ${word}`.length > maxCharacters) {
      lines.push(line);
      line = '';
    }
    while (word.length > maxCharacters) {
      if (line) {
        lines.push(line);
        line = '';
      }
      lines.push(word.slice(0, maxCharacters));
      word = word.slice(maxCharacters);
    }
    line = line ? `${line} ${word}` : word;
  });
  if (line) lines.push(line);
  return lines;
}

function generateChecklistPdf(checkOrChecks, reportSummary = null) {
  const checks = Array.isArray(checkOrChecks) ? checkOrChecks : [checkOrChecks];
  if (!checks.length) {
    throw new Error('Não há históricos para exportar.');
  }
  const pageWidth = 595;
  const pageHeight = 842;
  const left = 44;
  const right = pageWidth - 44;
  const colors = {
    orange: '0.941 0.416 0.129',
    dark: '0.153 0.137 0.125',
    muted: '0.430 0.400 0.380',
    line: '0.910 0.890 0.870',
    green: '0.090 0.400 0.278',
    red: '0.663 0.196 0.196',
  };
  const pages = [];
  let commands;
  let cursorY;

  const addText = (text, x, top, size, color = colors.dark, bold = false) => {
    const baseline = (pageHeight - top - size).toFixed(2);
    commands.push(`BT /${bold ? 'F2' : 'F1'} ${size} Tf ${color} rg 1 0 0 1 ${x.toFixed(2)} ${baseline} Tm <${pdfTextHex(text)}> Tj ET`);
  };
  const addLine = (x1, y1, x2, y2, color = colors.line, width = 0.7) => {
    commands.push(`${color} RG ${width} w ${x1} ${(pageHeight - y1).toFixed(2)} m ${x2} ${(pageHeight - y2).toFixed(2)} l S`);
  };
  const startPage = (check) => {
    commands = [];
    cursorY = 45;
    addText('MIZU', left, cursorY, 20, colors.orange, true);
    addText('CIMENTOS', left + 62, cursorY + 9, 9, colors.muted, true);
    addText('CHECKLIST DE EMPILHADEIRA', right - 212, cursorY + 7, 10, colors.dark, true);
    cursorY += 34;
    addLine(left, cursorY, right, cursorY, colors.orange, 1.5);
    cursorY += 19;
    addText('Relatório de inspeção pré-uso', left, cursorY, 14, colors.dark, true);
    cursorY += 23;
    addText(`Operador: ${check.operatorName}`, left, cursorY, 9);
    cursorY += 15;
    addText(`Data e hora: ${formatDate(check.createdAt)}`, left, cursorY, 9);
    const hasProblem = check.answers.some((answer) => answer.value === 'problem')
      || (check.safetyAnswers || []).some((answer) => answer.value === 'problem');
    addText(
      hasProblem ? 'RESULTADO: REQUER ATENÇÃO' : 'RESULTADO: SEM PROBLEMAS INFORMADOS',
      left,
      cursorY + 16,
      8,
      hasProblem ? colors.red : colors.green,
      true,
    );
    cursorY += 39;
    addLine(left, cursorY, right, cursorY);
    cursorY += 11;
  };
  const finishPage = () => {
    addLine(left, pageHeight - 49, right, pageHeight - 49);
    addText('Mizu Cimentos · Inspeção de empilhadeira', left, pageHeight - 39, 8, colors.muted);
    addText(`Página ${pages.length + 1}`, right - 45, pageHeight - 39, 8, colors.muted);
    pages.push(commands.join('\n'));
  };

  if (reportSummary) {
    commands = [];
    cursorY = 45;
    addText('MIZU', left, cursorY, 20, colors.orange, true);
    addText('CIMENTOS', left + 62, cursorY + 9, 9, colors.muted, true);
    addText('HISTÓRICO DE INSPEÇÕES', right - 180, cursorY + 7, 10, colors.dark, true);
    cursorY += 34;
    addLine(left, cursorY, right, cursorY, colors.orange, 1.5);
    cursorY += 26;
    addText('Relatório de histórico', left, cursorY, 16, colors.dark, true);
    cursorY += 34;
    [
      `Operador: ${reportSummary.operatorName}`,
      `Período: ${reportSummary.dateRange}`,
      `Inspeções incluídas: ${reportSummary.recordCount}`,
    ].forEach((detail) => {
      wrapPdfText(detail, 80).forEach((line) => {
        addText(line, left, cursorY, 10);
        cursorY += 18;
      });
    });
    cursorY += 6;
    addLine(left, cursorY, right, cursorY);
    cursorY += 18;
    addText('Os relatórios individuais das inspeções estão nas páginas seguintes.', left, cursorY, 9, colors.muted);
    finishPage();
  }

  const answerLabels = { ok: 'Conforme', problem: 'Não conforme', na: 'Não se aplica' };
  checks.forEach((check) => {
    startPage(check);
    check.answers.forEach((answer, index) => {
      const lines = wrapPdfText(`${String(index + 1).padStart(2, '0')}. ${answer.question}`, 70);
      const rowHeight = Math.max(19, lines.length * 11 + 6);
      if (cursorY + rowHeight > pageHeight - 72) {
        finishPage();
        startPage(check);
      }
      const answerColor = answer.value === 'problem'
        ? colors.red
        : answer.value === 'ok' ? colors.green : colors.muted;
      lines.forEach((line, lineIndex) => {
        addText(line, left, cursorY + lineIndex * 11, 8.5);
      });
      addText(answerLabels[answer.value] || 'Inválido', right - 95, cursorY, 8, answerColor, true);
      cursorY += rowHeight;
      addLine(left, cursorY - 2, right, cursorY - 2);
    });

    if (check.safetyAnswers?.length) {
      if (cursorY + 36 > pageHeight - 72) {
        finishPage();
        startPage(check);
      }
      cursorY += 7;
      addLine(left, cursorY, right, cursorY, colors.orange, 1.1);
      cursorY += 11;
      addText('EPIs e condições do operador', left, cursorY, 10, colors.dark, true);
      cursorY += 19;
      check.safetyAnswers.forEach((answer, index) => {
        const lines = wrapPdfText(`${String(index + 1).padStart(2, '0')}. ${answer.question}`, 70);
        const rowHeight = Math.max(19, lines.length * 11 + 6);
        if (cursorY + rowHeight > pageHeight - 72) {
          finishPage();
          startPage(check);
          addText('EPIs e condições do operador (continuação)', left, cursorY, 10, colors.dark, true);
          cursorY += 19;
        }
        const answerColor = answer.value === 'problem' ? colors.red : colors.green;
        lines.forEach((line, lineIndex) => {
          addText(line, left, cursorY + lineIndex * 11, 8.5);
        });
        addText(answerLabels[answer.value] || 'Inválido', right - 95, cursorY, 8, answerColor, true);
        cursorY += rowHeight;
        addLine(left, cursorY - 2, right, cursorY - 2);
      });
    }

    if (check.notes) {
      const noteLines = wrapPdfText(check.notes, 95);
      cursorY += 11;
      addText('Observações:', left, cursorY, 8.5, colors.dark, true);
      cursorY += 13;
      noteLines.forEach((line) => {
        if (cursorY + 12 > pageHeight - 63) {
          finishPage();
          startPage(check);
          addText('Observações (continuação):', left, cursorY, 8.5, colors.dark, true);
          cursorY += 13;
        }
        addText(line, left, cursorY, 8.5);
        cursorY += 12;
      });
    }
    finishPage();
  });

  const encoder = new TextEncoder();
  const objects = [
    encoder.encode('<< /Type /Catalog /Pages 2 0 R >>'),
    encoder.encode(`<< /Type /Pages /Kids [${pages.map((_, index) => `${5 + index * 2} 0 R`).join(' ')}] /Count ${pages.length} >>`),
    encoder.encode('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>'),
    encoder.encode('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>'),
  ];

  pages.forEach((content, index) => {
    const pageObjectId = 5 + index * 2;
    const contentObjectId = pageObjectId + 1;
    const contentBytes = encoder.encode(content);
    objects.push(encoder.encode(
      `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${pageWidth} ${pageHeight}] /Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> /Contents ${contentObjectId} 0 R >>`,
    ));
    objects.push(encoder.encode(`<< /Length ${contentBytes.length} >>\nstream\n${content}\nendstream`));
  });

  const chunks = [encoder.encode('%PDF-1.4\n')];
  const offsets = [0];
  let byteLength = chunks[0].length;
  objects.forEach((object, index) => {
    offsets.push(byteLength);
    const prefix = encoder.encode(`${index + 1} 0 obj\n`);
    const suffix = encoder.encode('\nendobj\n');
    chunks.push(prefix, object, suffix);
    byteLength += prefix.length + object.length + suffix.length;
  });
  const xrefOffset = byteLength;
  let xref = `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n`;
  offsets.slice(1).forEach((offset) => {
    xref += `${String(offset).padStart(10, '0')} 00000 n \n`;
  });
  xref += `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${xrefOffset}\n%%EOF\n`;
  chunks.push(encoder.encode(xref));
  return new Blob(chunks, { type: 'application/pdf' });
}

function downloadPdf(blob, filename) {
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = filename;
  document.body.append(link);
  link.click();
  link.remove();
  window.setTimeout(() => URL.revokeObjectURL(url), 1000);
}

function downloadChecklistPdf(check) {
  const filename = `checklist-empilhadeira-${new Date(check.createdAt).toISOString().replace(/[:.]/g, '-')}.pdf`;
  downloadPdf(generateChecklistPdf(check), filename);
}

function downloadHistoryPdf(checks, reportSummary) {
  const filenamePart = (value) => String(value)
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-zA-Z0-9]+/g, '-')
    .replace(/^-|-$/g, '')
    .toLowerCase();
  const filename = `historico-empilhadeira-${filenamePart(reportSummary.operatorName)}-${reportSummary.filenamePeriod}.pdf`;
  downloadPdf(generateChecklistPdf(checks, reportSummary), filename);
}

function normalizeWhatsAppNumber(value) {
  const raw = String(value).trim();
  const hasCountryCode = raw.startsWith('+') || raw.startsWith('00');
  let digits = raw.replace(/\D/g, '');
  if (digits.startsWith('00')) digits = digits.slice(2);
  if (!hasCountryCode && (digits.length === 10 || digits.length === 11)) digits = `55${digits}`;
  if (digits.length < 8 || digits.length > 15 || digits.startsWith('0')) {
    throw new Error('Informe um número válido com código do país. No Brasil, digite DDD e número (10 ou 11 dígitos).');
  }
  return digits;
}

function renderHistory(checks) {
  const container = byId('history-list');
  if (!checks.length) {
    container.innerHTML = '<div class="empty-state">Nenhuma inspeção encontrada para os filtros selecionados.</div>';
    return;
  }

  const canDeleteHistory = state.user?.role === 'admin' && state.user.username === 'lucas.santiago';
  container.innerHTML = checks.map((check) => {
    const hasProblem = check.answers.some((answer) => answer.value === 'problem')
      || (check.safetyAnswers || []).some((answer) => answer.value === 'problem');
    const resultLabel = hasProblem ? 'Requer atenção' : 'Sem problemas informados';
    const answerLabels = { ok: 'Conforme', problem: 'Não conforme', na: 'Não se aplica' };
    return `
      <article class="history-card">
        <div class="history-summary">
          <div class="history-meta">
            <strong>${escapeHtml(check.operatorName)}</strong>
            <span>${escapeHtml(formatDate(check.createdAt))}</span>
          </div>
          <div class="history-actions">
            <span class="history-badge ${hasProblem ? 'problem' : ''}">${resultLabel}</span>
            ${canDeleteHistory ? `<button class="button danger-outline" type="button" data-action="delete-check" data-check-id="${escapeHtml(check.id)}">Excluir histórico</button>` : ''}
          </div>
        </div>
        <details class="history-details">
          <summary>Ver respostas do checklist</summary>
          <ol class="answer-list">
            ${check.answers.map((answer) => `
              <li class="${answer.value === 'problem' ? 'answer-problem' : ''}">
                ${escapeHtml(answer.question)} — ${answerLabels[answer.value] || 'Inválido'}
              </li>
            `).join('')}
          </ol>
          ${check.safetyAnswers?.length ? `
          <strong>EPIs e condições</strong>
          <ol class="answer-list">
            ${check.safetyAnswers.map((answer) => `
              <li class="${answer.value === 'problem' ? 'answer-problem' : ''}">
                ${escapeHtml(answer.question)} — ${answerLabels[answer.value] || 'Inválido'}
              </li>
            `).join('')}
          </ol>` : ''}
          ${check.notes ? `<p class="check-note"><strong>Observação:</strong> ${escapeHtml(check.notes)}</p>` : ''}
        </details>
      </article>
    `;
  }).join('');
}

function applyHistoryFilters() {
  const operatorId = byId('operator-filter').value;
  const from = byId('from-filter').value;
  const to = byId('to-filter').value;
  state.visibleChecks = state.checks.filter((check) => {
    const localDate = new Date(check.createdAt);
    const date = [
      localDate.getFullYear(),
      String(localDate.getMonth() + 1).padStart(2, '0'),
      String(localDate.getDate()).padStart(2, '0'),
    ].join('-');
    return (!operatorId || check.operatorId === operatorId)
      && (!from || date >= from)
      && (!to || date <= to);
  });
  renderHistory(state.visibleChecks);
}

async function loadHistory() {
  hideNotice('history-alert');
  try {
    const result = await api('/api/checks');
    state.checks = result.checks;
    if (state.user.role === 'admin') {
      const users = await api('/api/users');
      state.users = users.users.filter((user) => user.role === 'operator');
      const select = byId('operator-filter');
      const selectedId = select.value;
      const operatorNames = new Map(state.users.map((user) => [user.id, user.displayName]));
      state.checks.forEach((check) => {
        if (!operatorNames.has(check.operatorId)) {
          operatorNames.set(check.operatorId, check.operatorName);
        }
      });
      const historyOperators = [...operatorNames.entries()]
        .sort((left, right) => left[1].localeCompare(right[1], 'pt-BR'));
      select.innerHTML = '<option value="">Todos os operadores</option>' + historyOperators.map(([id, name]) =>
        `<option value="${escapeHtml(id)}">${escapeHtml(name)}</option>`).join('');
      select.value = operatorNames.has(selectedId) ? selectedId : '';
      applyHistoryFilters();
    } else {
      state.visibleChecks = state.checks;
      renderHistory(state.visibleChecks);
    }
  } catch (error) {
    showHistoryNotice(error.message);
  }
}

async function loadUsers() {
  hideNotice('users-alert');
  try {
    const result = await api('/api/users');
    state.users = result.users;
    state.canAssignRoles = result.canAssignRoles;
    byId('new-user-role-field').hidden = !state.canAssignRoles;
    const managedUsers = state.users.filter((user) => user.username !== state.user.username);
    byId('users-list').innerHTML = managedUsers.length
      ? managedUsers.map((user) => `
        <article class="user-card">
          <div class="user-main">
            <div class="user-meta">
              <strong>${escapeHtml(user.displayName)}</strong>
              <span>Usuário: ${escapeHtml(user.username)}</span>
            </div>
            <span class="user-role ${user.role === 'admin' ? 'admin-role' : ''}">${user.role === 'admin' ? 'Administrador' : 'Operador'}${user.mustChangePassword ? ' · aguardando troca de senha' : ''}</span>
          </div>
          <div class="user-actions">
            ${state.canAssignRoles || user.role === 'operator' ? `
              <button class="button outline" type="button" data-action="show-reset" data-user-id="${escapeHtml(user.id)}">Redefinir senha</button>
              <button class="button danger-outline" type="button" data-action="delete-user" data-user-id="${escapeHtml(user.id)}">Excluir acesso</button>
            ` : '<span class="muted">Somente lucas.santiago pode gerenciar outros administradores.</span>'}
          </div>
          ${state.canAssignRoles ? `
          <form class="role-form" data-user-id="${escapeHtml(user.id)}">
            <label>Perfil
              <select name="role">
                <option value="operator" ${user.role === 'operator' ? 'selected' : ''}>Operador</option>
                <option value="admin" ${user.role === 'admin' ? 'selected' : ''}>Administrador</option>
              </select>
            </label>
            <button class="button secondary" type="submit">Salvar perfil</button>
          </form>` : ''}
          <form class="reset-password-form" data-user-id="${escapeHtml(user.id)}" hidden>
            <label>Nova senha temporária
              <input name="temporaryPassword" type="password" required minlength="8" maxlength="200" autocomplete="new-password">
            </label>
            <label>Confirme a senha temporária
              <input name="confirmPassword" type="password" required minlength="8" maxlength="200" autocomplete="new-password">
            </label>
            <div class="reset-actions">
              <button class="button primary" type="submit">Salvar senha temporária</button>
              <button class="button outline" type="button" data-action="cancel-reset" data-user-id="${escapeHtml(user.id)}">Cancelar</button>
            </div>
          </form>
        </article>`).join('')
      : '<div class="empty-state">Nenhum outro usuário cadastrado. Crie os acessos acima.</div>';
  } catch (error) {
    showNotice('users-alert', error.message);
  }
}

byId('login-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  hideNotice('login-alert');
  const button = event.currentTarget.querySelector('button[type="submit"]');
  button.disabled = true;
  try {
    const form = new FormData(event.currentTarget);
    const result = await api('/api/login', {
      method: 'POST',
      body: JSON.stringify({
        username: form.get('username'),
        password: form.get('password'),
      }),
    });
    state.user = result.user;
    if (state.user.mustChangePassword) {
      byId('login-view').hidden = true;
      byId('password-view').hidden = false;
    } else {
      renderApp();
    }
  } catch (error) {
    showNotice('login-alert', error.message);
  } finally {
    button.disabled = false;
  }
});

byId('password-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  hideNotice('password-alert');
  const formElement = event.currentTarget;
  const form = new FormData(formElement);
  const newPassword = String(form.get('newPassword'));
  if (newPassword !== form.get('confirmPassword')) {
    showNotice('password-alert', 'A confirmação da nova senha não corresponde.');
    return;
  }
  try {
    const result = await api('/api/password', {
      method: 'POST',
      body: JSON.stringify({
        currentPassword: form.get('currentPassword'),
        newPassword,
      }),
    });
    state.user = result.user;
    formElement.reset();
    renderApp();
  } catch (error) {
    showNotice('password-alert', error.message);
  }
});

byId('logout-button').addEventListener('click', async () => {
  try {
    await api('/api/logout', { method: 'POST', body: '{}' });
  } catch (error) {
    showNotice('history-alert', error.message);
  }
  state.user = null;
  byId('app-view').hidden = true;
  byId('password-view').hidden = true;
  byId('login-view').hidden = false;
  byId('login-form').reset();
});

byId('check-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  hideNotice('check-alert');
  hideNotice('check-success');
  const formElement = event.currentTarget;
  if (!formElement.checkValidity()) {
    const invalidField = formElement.querySelector(':invalid');
    const tabPanel = invalidField?.closest('.check-tab-panel');
    if (tabPanel) setCheckTab(tabPanel.id);
    formElement.reportValidity();
    return;
  }
  const button = byId('submit-check');
  button.disabled = true;
  try {
    const answers = state.questions.map((question) => ({
      itemId: question.id,
      value: new FormData(formElement).get(`answer-${question.id}`),
    }));
    const safetyAnswers = state.safetyQuestions.map((question) => ({
      itemId: question.id,
      value: new FormData(formElement).get(`safety-${question.id}`),
    }));
    const result = await api('/api/checks', {
      method: 'POST',
      body: JSON.stringify({
        answers,
        safetyAnswers,
        notes: byId('check-notes').value,
      }),
    });
    state.lastCheck = result.check;
    formElement.reset();
    showNotice('check-success', `Inspeção registrada em ${formatDate(result.check.createdAt)}.`);
    byId('report-share').hidden = false;
    byId('report-share').scrollIntoView({ behavior: 'smooth', block: 'center' });
  } catch (error) {
    showNotice('check-alert', error.message);
  } finally {
    button.disabled = false;
  }
});

byId('download-report').addEventListener('click', () => {
  if (!state.lastCheck) {
    showNotice('check-alert', 'Registre um checklist antes de gerar o relatório.');
    return;
  }
  try {
    downloadChecklistPdf(state.lastCheck);
  } catch (error) {
    showNotice('check-alert', `Não foi possível gerar ou baixar o PDF: ${error.message}`);
  }
});

byId('send-whatsapp').addEventListener('click', () => {
  if (!state.lastCheck) {
    showNotice('check-alert', 'Registre um checklist antes de compartilhar o relatório.');
    return;
  }
  let recipient;
  try {
    recipient = normalizeWhatsAppNumber(byId('whatsapp-number').value);
  } catch (error) {
    showNotice('check-alert', error.message);
    byId('whatsapp-number').focus();
    return;
  }

  const check = state.lastCheck;
  const reportName = `checklist-empilhadeira-${new Date(check.createdAt).toISOString().slice(0, 10)}.pdf`;
  const message = `Segue o checklist da empilhadeira de ${check.operatorName}, realizado em ${formatDate(check.createdAt)}. Estou baixando o relatório PDF para anexar nesta conversa.`;
  const whatsappUrl = `https://wa.me/${recipient}?text=${encodeURIComponent(message)}`;
  const openedWindow = window.open(whatsappUrl, '_blank');

  if (!openedWindow) {
    showNotice('check-alert', 'O navegador bloqueou a abertura do WhatsApp. Permita pop-ups para este site e tente novamente.');
    return;
  }
  openedWindow.opener = null;
  try {
    downloadChecklistPdf(check);
  } catch (error) {
    openedWindow.close();
    showNotice('check-alert', `Não foi possível gerar ou baixar o PDF: ${error.message}`);
    return;
  }
  showNotice(
    'check-success',
    `Relatório ${reportName} baixado. A conversa do WhatsApp foi aberta; anexe o PDF antes de enviar.`,
  );
});

document.querySelectorAll('.tab').forEach((tab) => {
  tab.addEventListener('click', () => setView(tab.dataset.view));
});
function setCheckTab(panelId) {
  document.querySelectorAll('.check-tab').forEach((tab) => {
    const active = tab.dataset.checkTab === panelId;
    tab.classList.toggle('active', active);
    tab.setAttribute('aria-selected', String(active));
  });
  document.querySelectorAll('.check-tab-panel').forEach((panel) => {
    panel.hidden = panel.id !== panelId;
  });
}
document.querySelectorAll('.check-tab').forEach((tab) => {
  tab.addEventListener('click', () => setCheckTab(tab.dataset.checkTab));
});
byId('refresh-history').addEventListener('click', loadHistory);
byId('refresh-users').addEventListener('click', loadUsers);
byId('apply-filters').addEventListener('click', applyHistoryFilters);
byId('export-pdf').addEventListener('click', () => {
  applyHistoryFilters();
  if (!state.visibleChecks.length) {
    showHistoryNotice('Não há históricos para exportar com os filtros selecionados.');
    return;
  }
  const selectedOperator = byId('operator-filter');
  const operatorName = selectedOperator.value
    ? selectedOperator.selectedOptions[0].textContent
    : 'Todos os operadores';
  const from = byId('from-filter').value;
  const to = byId('to-filter').value;
  const displayDate = (value) => value
    ? new Intl.DateTimeFormat('pt-BR').format(new Date(`${value}T00:00:00`))
    : '';
  const dateRange = from && to
    ? `${displayDate(from)} até ${displayDate(to)}`
    : from
      ? `A partir de ${displayDate(from)}`
      : to
        ? `Até ${displayDate(to)}`
        : 'Todo o período';
  const filenamePeriod = `${from || 'inicio'}-${to || 'sem-limite'}`;
  try {
    downloadHistoryPdf(state.visibleChecks, {
      operatorName,
      dateRange,
      filenamePeriod,
      recordCount: state.visibleChecks.length,
    });
  } catch (error) {
    showHistoryNotice(`Não foi possível gerar ou baixar o PDF: ${error.message}`);
  }
});

byId('history-list').addEventListener('click', async (event) => {
  const button = event.target.closest('button[data-action="delete-check"]');
  if (!button) return;

  const checkId = button.dataset.checkId;
  const check = state.visibleChecks.find((item) => item.id === checkId);
  if (!check) {
    showHistoryNotice('Não foi possível localizar o histórico selecionado. Atualize a lista e tente novamente.');
    return;
  }
  if (!window.confirm(`Excluir o histórico de ${check.operatorName}, realizado em ${formatDate(check.createdAt)}? Esta ação não pode ser desfeita.`)) return;

  button.disabled = true;
  hideNotice('history-alert');
  try {
    await api(`/api/checks/${encodeURIComponent(checkId)}`, { method: 'DELETE' });
    state.checks = state.checks.filter((item) => item.id !== checkId);
    state.visibleChecks = state.visibleChecks.filter((item) => item.id !== checkId);
    renderHistory(state.visibleChecks);
    showHistoryNotice('Histórico excluído.', 'success');
  } catch (error) {
    showHistoryNotice(error.message);
    button.disabled = false;
  }
});

byId('users-list').addEventListener('click', async (event) => {
  const button = event.target.closest('button[data-action]');
  if (!button) return;

  const { action, userId } = button.dataset;
  const card = button.closest('.user-card');
  if (action === 'show-reset') {
    const form = card.querySelector('.reset-password-form');
    form.hidden = false;
    form.querySelector('input[name="temporaryPassword"]').focus();
    return;
  }
  if (action === 'cancel-reset') {
    const form = card.querySelector('.reset-password-form');
    form.reset();
    form.hidden = true;
    return;
  }
  if (action === 'delete-user') {
    const name = card.querySelector('.user-meta strong').textContent;
    if (!window.confirm(`Excluir o acesso de ${name}? Os checklists existentes serão preservados no histórico.`)) return;

    button.disabled = true;
    hideNotice('users-alert');
    try {
      const result = await api(`/api/users/${encodeURIComponent(userId)}`, { method: 'DELETE' });
      await loadUsers();
      showNotice('users-alert', `Acesso de ${result.displayName} excluído. Os checklists anteriores foram preservados no histórico.`);
      byId('users-alert').classList.remove('error');
      byId('users-alert').classList.add('success');
    } catch (error) {
      byId('users-alert').classList.remove('success');
      byId('users-alert').classList.add('error');
      showNotice('users-alert', error.message);
      button.disabled = false;
    }
  }
});

byId('users-list').addEventListener('submit', async (event) => {
  const roleForm = event.target.closest('.role-form');
  if (roleForm) {
    event.preventDefault();
    hideNotice('users-alert');
    const selectedRole = new FormData(roleForm).get('role');
    const targetUser = state.users.find((user) => user.id === roleForm.dataset.userId);
    if (!targetUser) {
      showNotice('users-alert', 'Não foi possível localizar o usuário selecionado. Atualize a lista e tente novamente.');
      return;
    }
    if (selectedRole !== targetUser.role) {
      const description = selectedRole === 'admin'
        ? `Conceder acesso de administrador a ${targetUser.displayName}?`
        : `Alterar o perfil de ${targetUser.displayName} para operador?`;
      if (!window.confirm(`${description} As sessões atuais desse usuário serão encerradas.`)) {
        roleForm.querySelector('select[name="role"]').value = targetUser.role;
        return;
      }
    }

    const button = roleForm.querySelector('button[type="submit"]');
    button.disabled = true;
    try {
      const result = await api(`/api/users/${encodeURIComponent(roleForm.dataset.userId)}/role`, {
        method: 'PATCH',
        body: JSON.stringify({ role: selectedRole }),
      });
      await loadUsers();
      const roleName = result.user.role === 'admin' ? 'administrador' : 'operador';
      showNotice('users-alert', `Perfil de ${result.user.displayName} atualizado para ${roleName}. O usuário deverá entrar novamente.`);
      byId('users-alert').classList.remove('error');
      byId('users-alert').classList.add('success');
    } catch (error) {
      byId('users-alert').classList.remove('success');
      byId('users-alert').classList.add('error');
      showNotice('users-alert', error.message);
      button.disabled = false;
    }
    return;
  }

  const formElement = event.target.closest('.reset-password-form');
  if (!formElement) return;
  event.preventDefault();
  hideNotice('users-alert');

  const form = new FormData(formElement);
  const temporaryPassword = String(form.get('temporaryPassword'));
  if (temporaryPassword !== form.get('confirmPassword')) {
    showNotice('users-alert', 'A confirmação da senha temporária não corresponde.');
    return;
  }

  const button = formElement.querySelector('button[type="submit"]');
  button.disabled = true;
  try {
    const result = await api(`/api/users/${encodeURIComponent(formElement.dataset.userId)}/reset-password`, {
      method: 'POST',
      body: JSON.stringify({ temporaryPassword }),
    });
    await loadUsers();
    showNotice('users-alert', `Senha redefinida para ${result.user.displayName}. O operador deverá trocá-la no próximo acesso.`);
    byId('users-alert').classList.remove('error');
    byId('users-alert').classList.add('success');
  } catch (error) {
    byId('users-alert').classList.remove('success');
    byId('users-alert').classList.add('error');
    showNotice('users-alert', error.message);
    button.disabled = false;
  }
});

byId('user-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  hideNotice('users-alert');
  const formElement = event.currentTarget;
  const form = new FormData(formElement);
  const button = formElement.querySelector('button[type="submit"]');
  button.disabled = true;
  try {
    const result = await api('/api/users', {
      method: 'POST',
      body: JSON.stringify({
        displayName: form.get('displayName'),
        username: form.get('username'),
        temporaryPassword: form.get('temporaryPassword'),
        role: state.canAssignRoles ? form.get('role') : 'operator',
      }),
    });
    formElement.reset();
    await loadUsers();
    const roleName = result.user.role === 'admin' ? 'administrador' : 'operador';
    showNotice('users-alert', `Acesso de ${result.user.displayName} criado como ${roleName}. Entregue o usuário e a senha temporária em particular.`);
    byId('users-alert').classList.remove('error');
    byId('users-alert').classList.add('success');
  } catch (error) {
    byId('users-alert').classList.remove('success');
    byId('users-alert').classList.add('error');
    showNotice('users-alert', error.message);
  } finally {
    button.disabled = false;
  }
});

async function start() {
  try {
    const [session, questionResult] = await Promise.all([
      api('/api/session'),
      api('/api/questions'),
    ]);
    state.questions = questionResult.questions;
    state.safetyQuestions = questionResult.safetyQuestions;
    state.user = session.user;
    if (!state.user) {
      byId('login-view').hidden = false;
    } else if (state.user.mustChangePassword) {
      byId('password-view').hidden = false;
    } else {
      renderApp();
    }
  } catch (error) {
    byId('login-view').hidden = false;
    showNotice('login-alert', `Não foi possível conectar ao servidor: ${error.message}`);
  }
}

start();
