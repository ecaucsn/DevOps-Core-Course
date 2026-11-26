(function () {
  "use strict";

  const STORAGE_KEY = "devopsCourse.v1";
  let state = loadState();
  let phaseFilter = "all";
  let query = "";

  const els = {
    labs: document.getElementById("labs"),
    filters: document.getElementById("filters"),
    search: document.getElementById("search"),
    labBar: document.getElementById("lab-progress"),
    labText: document.getElementById("lab-progress-text"),
    taskBar: document.getElementById("task-progress"),
    taskText: document.getElementById("task-progress-text"),
    doneLabs: document.getElementById("done-labs"),
    doneTasks: document.getElementById("done-tasks"),
    exportBtn: document.getElementById("export"),
    importBtn: document.getElementById("import"),
    importFile: document.getElementById("import-file"),
    resetBtn: document.getElementById("reset"),
  };

  function loadState() {
    try {
      const raw = JSON.parse(localStorage.getItem(STORAGE_KEY));
      if (raw && typeof raw === "object" && raw.labs) return raw;
    } catch (e) {
      /* ignore corrupted state */
    }
    return { labs: {} };
  }

  function saveState() {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
  }

  function labState(n) {
    const key = String(n);
    if (!state.labs[key] || typeof state.labs[key] !== "object") {
      state.labs[key] = { status: "todo", tasks: {}, notes: "" };
    }
    const s = state.labs[key];
    if (!s.tasks || typeof s.tasks !== "object") s.tasks = {};
    if (typeof s.notes !== "string") s.notes = "";
    if (!s.status) s.status = "todo";
    return s;
  }

  function esc(value) {
    return String(value).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }

  function lectureUrl(n) {
    return COURSE.repo + "/lectures/lec" + n + ".md";
  }

  function labUrl(n) {
    return COURSE.repo + "/labs/lab" + String(n).padStart(2, "0") + ".md";
  }

  function phaseName(id) {
    const p = COURSE.phases.find(function (x) {
      return x.id === id;
    });
    return p ? p.name : id;
  }

  function totalTasks() {
    return COURSE.labs.reduce(function (sum, lab) {
      return sum + lab.tasks.length;
    }, 0);
  }

  function doneTasks() {
    return COURSE.labs.reduce(function (sum, lab) {
      const s = labState(lab.n);
      const done = lab.tasks.reduce(function (acc, _t, i) {
        return acc + (s.tasks[i] ? 1 : 0);
      }, 0);
      return sum + done;
    }, 0);
  }

  function doneLabs() {
    return COURSE.labs.filter(function (lab) {
      return labState(lab.n).status === "done";
    }).length;
  }

  function renderFilters() {
    const items = [{ id: "all", name: "Все" }].concat(COURSE.phases);
    els.filters.innerHTML = items
      .map(function (p) {
        const active = phaseFilter === p.id ? " active" : "";
        const range = p.range ? '<span class="filter-range">' + esc(p.range) + "</span>" : "";
        return (
          '<button type="button" class="filter' + active + '" data-phase="' + p.id + '">' +
          esc(p.name) + range + "</button>"
        );
      })
      .join("");
  }

  function cardHtml(lab) {
    const s = labState(lab.n);
    const concepts = lab.concepts
      .map(function (c) {
        return '<span class="chip">' + esc(c) + "</span>";
      })
      .join("");
    const tasks = lab.tasks
      .map(function (t, i) {
        const checked = s.tasks[i] ? " checked" : "";
        return (
          '<li><label><input type="checkbox" data-action="task" data-lab="' + lab.n +
          '" data-idx="' + i + '"' + checked + "><span>" + esc(t) + "</span></label></li>"
        );
      })
      .join("");
    const commands = lab.commands
      .map(function (c) {
        return (
          '<div class="cmd"><code>' + esc(c) + '</code>' +
          '<button type="button" class="copy" data-copy="' + esc(c) + '">Копировать</button></div>'
        );
      })
      .join("");

    return (
      '<article class="card" data-lab="' + lab.n + '">' +
      '<header class="card-head"><div>' +
      '<span class="week">Неделя ' + lab.week + " · Лаб. " + lab.n + "</span>" +
      "<h3>" + esc(lab.title) + "</h3>" +
      '<span class="phase-tag">' + esc(phaseName(lab.phase)) + "</span>" +
      "</div>" +
      '<select class="status" data-action="status" data-lab="' + lab.n + '">' +
      '<option value="todo">Не начато</option>' +
      '<option value="in-progress">В процессе</option>' +
      '<option value="done">Готово</option>' +
      "</select></header>" +
      '<div class="links">' +
      '<a href="' + lectureUrl(lab.lecture) + '" target="_blank" rel="noopener">Лекция ' + lab.lecture + "</a>" +
      '<a href="' + labUrl(lab.n) + '" target="_blank" rel="noopener">Лабораторная</a>' +
      "</div>" +
      '<div class="chips">' + concepts + "</div>" +
      '<ul class="tasks">' + tasks + "</ul>" +
      '<details class="commands"><summary>Команды</summary>' + commands + "</details>" +
      '<label class="notes-label">Заметки' +
      '<textarea data-action="notes" data-lab="' + lab.n + '" rows="3" ' +
      'placeholder="Что понял, где застрял..."></textarea></label>' +
      "</article>"
    );
  }

  function renderLabs() {
    const q = query.trim().toLowerCase();
    const visible = COURSE.labs.filter(function (lab) {
      const phaseOk = phaseFilter === "all" || lab.phase === phaseFilter;
      const haystack = (lab.title + " " + lab.concepts.join(" ") + " " + lab.tasks.join(" ")).toLowerCase();
      const queryOk = !q || haystack.indexOf(q) !== -1;
      return phaseOk && queryOk;
    });

    if (!visible.length) {
      els.labs.innerHTML = '<p class="empty">Ничего не найдено. Измените фильтр или запрос.</p>';
      return;
    }

    els.labs.innerHTML = visible.map(cardHtml).join("");

    els.labs.querySelectorAll('select[data-action="status"]').forEach(function (sel) {
      sel.value = labState(Number(sel.dataset.lab)).status;
    });
    els.labs.querySelectorAll('textarea[data-action="notes"]').forEach(function (ta) {
      ta.value = labState(Number(ta.dataset.lab)).notes;
    });
  }

  function updateProgress() {
    const labsTotal = COURSE.labs.length;
    const labsDone = doneLabs();
    const tasksTotal = totalTasks();
    const tasksDone = doneTasks();

    const labPct = labsTotal ? Math.round((labsDone / labsTotal) * 100) : 0;
    const taskPct = tasksTotal ? Math.round((tasksDone / tasksTotal) * 100) : 0;

    els.labBar.style.width = labPct + "%";
    els.taskBar.style.width = taskPct + "%";
    els.labText.textContent = labsDone + " / " + labsTotal + " лаб (" + labPct + "%)";
    els.taskText.textContent = tasksDone + " / " + tasksTotal + " задач (" + taskPct + "%)";
    els.doneLabs.textContent = labsDone;
    els.doneTasks.textContent = tasksDone;
  }

  function render() {
    renderFilters();
    renderLabs();
    updateProgress();
  }

  els.filters.addEventListener("click", function (e) {
    const btn = e.target.closest("[data-phase]");
    if (!btn) return;
    phaseFilter = btn.dataset.phase;
    render();
  });

  els.search.addEventListener("input", function (e) {
    query = e.target.value;
    renderLabs();
  });

  els.labs.addEventListener("change", function (e) {
    const t = e.target;
    const n = Number(t.dataset.lab);
    if (!n) return;
    const s = labState(n);
    if (t.dataset.action === "status") s.status = t.value;
    if (t.dataset.action === "task") s.tasks[t.dataset.idx] = t.checked;
    saveState();
    updateProgress();
  });

  els.labs.addEventListener("input", function (e) {
    const t = e.target;
    if (t.dataset.action !== "notes") return;
    labState(Number(t.dataset.lab)).notes = t.value;
    saveState();
  });

  els.labs.addEventListener("click", function (e) {
    const btn = e.target.closest("[data-copy]");
    if (!btn) return;
    const text = btn.dataset.copy;
    const done = function () {
      const old = btn.textContent;
      btn.textContent = "Скопировано";
      setTimeout(function () {
        btn.textContent = old;
      }, 1200);
    };
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(done).catch(function () {});
    } else {
      const ta = document.createElement("textarea");
      ta.value = text;
      document.body.appendChild(ta);
      ta.select();
      document.execCommand("copy");
      document.body.removeChild(ta);
      done();
    }
  });

  els.exportBtn.addEventListener("click", function () {
    const blob = new Blob([JSON.stringify(state, null, 2)], { type: "application/json" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = "devops-progress.json";
    a.click();
    URL.revokeObjectURL(url);
  });

  els.importBtn.addEventListener("click", function () {
    els.importFile.click();
  });

  els.importFile.addEventListener("change", function (e) {
    const file = e.target.files && e.target.files[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = function () {
      try {
        const parsed = JSON.parse(String(reader.result));
        if (parsed && typeof parsed === "object" && parsed.labs) {
          state = parsed;
          saveState();
          render();
          alert("Прогресс импортирован.");
        } else {
          alert("Неверный формат файла.");
        }
      } catch (err) {
        alert("Не удалось прочитать файл: " + err.message);
      }
    };
    reader.readAsText(file);
    e.target.value = "";
  });

  els.resetBtn.addEventListener("click", function () {
    if (!confirm("Сбросить весь прогресс и заметки? Это действие необратимо.")) return;
    state = { labs: {} };
    saveState();
    render();
  });

  render();
})();
