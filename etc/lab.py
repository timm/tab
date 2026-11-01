#!/usr/bin/env python3
"""lab.py: run tab.lua's configs, keep what they said, page back
through them.  Two faces over one engine: batch, for scripts and
sweeps, and a terminal ui, for looking.

A config is tab.lua's own command line, so nothing here knows what
a flag means.  Each run is one json file under $TAB_RUNS (default
$CACHE/lab/runs): its config, its command, its output, its seconds.
Nothing is overwritten, so the store is the whole history.

usage: python3 etc/lab.py ui                  the terminal front end
       python3 etc/lab.py run   [k=v ...]     one run, stored
       python3 etc/lab.py sweep [k=v,v ...]   every combination
       python3 etc/lab.py ls                  the runs, newest first
       python3 etc/lab.py show  [n]           run n, in full
       python3 etc/lab.py plot  [n] [ascii]   run n's csv, drawn
       python3 etc/lab.py save  name [k=v..]  a config, by name
       python3 etc/lab.py load  name          print it back
"""
import itertools, json, os, shutil, subprocess, sys, time
from pathlib import Path

Root  = Path(__file__).resolve().parent.parent
Cache = Path(os.environ.get("CACHE") or "~/tmp/cache").expanduser()
Runs  = Path(os.environ.get("TAB_RUNS") or Cache / "lab/runs")
Confs = Runs.parent / "configs"
Png   = str(Runs.parent / "plot.png")

# the flags of tab.lua's help, and tab-eg.lua's force
Flags = [("go",     "rmeans"), ("bins",  "7"), ("budget", "50"),
         ("check",  "5"), ("decs", "2"), ("m", "2"), ("p", "2"),
         ("seed",   "1234567891"), ("force", ""),
         ("file",   "~/gits/moot/optimize/misc/auto93.csv"),
         ("args",   "")]                 # the words an action takes

# tab-eg.lua's rigs, then tab.lua's own actions
Goes = ["rmeans", "rmeansall", "nb", "nbauc", "splits", "report",
        "--all", "--secs", "-h"]

# ---- configs ----------------------------------------------------
def config(args=(), base=None):
  "The defaults, then a saved config, then any k=v arguments."
  cfg = dict(Flags) if base is None else dict(base)
  for s in args:
    if "=" in s:
      k, v = s.split("=", 1); cfg[k] = v
  return cfg

def command(cfg):
  "The argv a config means: an action of tab.lua, else a rig."
  go   = cfg.get("go", "rmeans")
  more = str(cfg.get("args", "")).split()      # only an action takes
  args = [f"{k}={v}" for k, v in cfg.items()   # words of its own
          if k not in ("go", "args") and str(v).strip() != ""]
  if go.startswith("-"):
    return ["lua", "tab.lua", *args, go, *more]
  return ["luajit", "tab-eg.lua", *args, f"go={go}"]

def summary(cfg, skip=("go", "args")):
  "The config on one line, a long file name cut to its name."
  return " ".join(f"{k}={Path(v).name if k == 'file' else v}"
                  for k, v in cfg.items()
                  if k not in skip and str(v).strip() != "")

def save(name, cfg):
  "Keep a config under a name."
  Confs.mkdir(parents=True, exist_ok=True)
  f = Confs / f"{name}.json"
  f.write_text(json.dumps(cfg, indent=2))
  return f

def load(name):
  "That config, back again."
  return json.loads((Confs / f"{name}.json").read_text())

def saved():
  "Every saved config's name."
  return sorted(f.stem for f in Confs.glob("*.json"))

# ---- runs -------------------------------------------------------
def slot():
  "A free file name, so two runs in one second both survive."
  Runs.mkdir(parents=True, exist_ok=True)
  stem, n = time.strftime("%Y%m%d-%H%M%S"), 0
  while (Runs / f"{stem}-{n:02d}.json").exists(): n += 1
  return Runs / f"{stem}-{n:02d}.json"

def run(cfg):
  "Run one config; store what it said; return that record."
  cmd, t0 = command(cfg), time.time()
  try:
    p = subprocess.run(cmd, cwd=Root, capture_output=True, text=True)
    code, out, err = p.returncode, p.stdout, p.stderr
  except OSError as e:
    code, out, err = -1, "", str(e)
  r = {"when": time.strftime("%Y-%m-%d %H:%M:%S"), "cfg": cfg,
       "cmd": cmd, "code": code, "secs": time.time() - t0,
       "out": out, "err": err}
  f = slot(); r["path"] = str(f)
  f.write_text(json.dumps(r, indent=2))
  return r

def sweep(args, base=None):
  "One run per combination of the comma separated values given."
  axes = []
  for s in args:
    if "=" in s:
      k, v = s.split("=", 1); axes.append([(k, x) for x in v.split(",")])
  for combo in itertools.product(*axes) if axes else [()]:
    yield run(config([f"{k}={v}" for k, v in combo], base))

def runs():
  "Every stored run, newest first."
  out = []
  for f in sorted(Runs.glob("*.json"), reverse=True):
    try:    out.append(json.loads(f.read_text()))
    except (OSError, ValueError): pass
  return out

# ---- plots ------------------------------------------------------
def result(r):
  "The result csv a run printed, if it printed one."
  for line in (r.get("out") or "").splitlines():
    f = line.strip()
    if f.endswith(".csv") and Path(f).exists(): return f
  return None

def script(csv, w, h, pix):
  "A gnuplot deck: every scored column against the rep, over csv."
  cols = Path(csv).read_text().splitlines()[0].split(",")
  term = (f"set term pngcairo size {w * 9},{h * 18}; "
          f"set output '{Png}'" if pix else
          f"set term dumb size {w},{h}")
  draw = ", ".join(
    f"'{csv}' every ::1 using 1:{i + 1} with linespoints title '{c}'"
    for i, c in enumerate(cols) if c not in ("rep", "secs"))
  return (f"{term}\nset datafile separator ','\nset key outside\n"
          f"set xlabel 'rep'\nplot {draw}\n")

def plotted(csv, w=70, h=18, pix=False):
  "That deck, drawn: chafa's pixels if we have them, else ascii."
  pix = pix and bool(shutil.which("chafa"))
  p = subprocess.run(["gnuplot", "-"], input=script(csv, w, h, pix),
                     capture_output=True, text=True)
  if p.returncode: return p.stderr or "gnuplot said nothing"
  if not pix: return p.stdout
  q = subprocess.run(["chafa", "-f", "symbols", "--animate", "off",
                      "-s", f"{w}x{h}", Png], capture_output=True,
                     text=True)
  return q.stdout or q.stderr

# ---- batch ------------------------------------------------------
def tell(r):
  "One run, as one line."
  return (f'{r["when"][5:16]}  {r["cfg"].get("go","?"):<10}'
          f'{r["secs"]:7.2f}s  exit {r["code"]}  {summary(r["cfg"])}')

def main(argv):
  "The batch face.  Anything not listed here is the usage."
  what, rest = (argv + ["ls"])[0], argv[1:]
  if   what == "ui":    return ui()
  elif what == "run":   print(tell(run(config(rest))))
  elif what == "sweep":
    for r in sweep(rest): print(tell(r))
  elif what == "ls":
    for r in runs(): print(tell(r))
  elif what in ("show", "plot"):
    all = runs()
    n   = int(rest[0]) if rest and rest[0].isdigit() else 0
    if not all: return print("no runs yet")
    r = all[min(n, len(all) - 1)]
    if what == "show":
      print(" ".join(r["cmd"])); print(tell(r)); print(r["out"], end="")
      if r["err"]: print(r["err"], file=sys.stderr)
    else:
      csv = result(r)
      print(plotted(csv, pix="pix" in rest) if csv
            else "that run printed no csv")
  elif what == "save" and rest:
    print(save(rest[0], config(rest[1:])))
  elif what == "load" and rest:
    print(json.dumps(load(rest[0]), indent=2))
  else: print(__doc__)

# ---- ui ---------------------------------------------------------
def ui(start=True):
  """The terminal face.  Everything textual lives in here, so batch
  runs on a box with no textual installed.  `start=False` hands the
  class back instead of running it, which is how the tests drive it."""
  from rich.text import Text
  from textual import on, work
  from textual.app import App
  from textual.containers import Horizontal, Vertical, VerticalScroll
  from textual.screen import ModalScreen
  from textual.widgets import (Button, DataTable, Footer, Header,
                               Input, Label, ListItem, ListView,
                               RichLog, Select, Static)

  class Ask(ModalScreen[str]):
    "One line in: a name for a config."
    def compose(self):
      yield Vertical(Label("save config as:"), Input(id="name"),
                     id="ask")
    @on(Input.Submitted)
    def done(self, e): self.dismiss(e.value.strip())
    def key_escape(self): self.dismiss("")

  class Pick(ModalScreen[str]):
    "One of the saved configs, or nothing."
    def compose(self):
      self.names = saved()
      yield Vertical(Label("load config:"),
                     ListView(*[ListItem(Label(n)) for n in self.names],
                              id="names"), id="ask")
    @on(ListView.Selected)
    def done(self, e): self.dismiss(self.names[e.list_view.index or 0])
    def key_escape(self): self.dismiss("")

  class Plot(ModalScreen[None]):
    "One plot, full screen, until escape."
    BINDINGS = [("escape,q,g", "dismiss", "close")]
    def __init__(self, title, body):
      super().__init__(); self.t, self.b = title, body
    def compose(self):
      yield Vertical(Label(self.t), Static(Text.from_ansi(self.b)),
                     id="plot")

  class Tui(App):
    """The config on the left, the runs on the right.  A run is a
    subprocess, so the table stays live while lua works."""
    CSS = """
    #config { width: 34; border-right: solid $accent; }
    #config Input { width: 1fr; }
    #runs { height: 40%; }
    #out { border-top: solid $accent; }
    #ask { background: $panel; border: thick $accent; padding: 1 2;
           width: 60; height: auto; }
    #plot { background: $surface; padding: 0 1; }
    """
    BINDINGS = [("r", "run", "run"), ("s", "save", "save config"),
                ("l", "load", "load config"), ("g", "plot", "plot"),
                ("G", "ascii", "plot, ascii"),
                ("n", "next", "next run"), ("p", "prev", "prev run"),
                ("D", "drop", "delete run"), ("q", "quit", "quit")]

    def compose(self):
      yield Header()
      with Horizontal():
        with VerticalScroll(id="config"):
          for k, v in Flags:
            yield Label(k)
            if k == "go":
              yield Select([(g, g) for g in Goes], value=v,
                           allow_blank=False, id="f-go")
            else:
              yield Input(value=v, id=f"f-{k}")
          yield Button("run", variant="primary", id="go-btn")
        with Vertical():
          yield DataTable(id="runs", cursor_type="row")
          yield RichLog(id="out", wrap=True, markup=True)
      yield Footer()

    def on_mount(self):
      t = self.query_one("#runs", DataTable)
      t.add_columns("when", "go", "secs", "exit", "config")
      self.reload()

    # ---- config -------------------------------------------------
    def config(self):
      "What the left hand pane says, right now."
      cfg = {"go": self.query_one("#f-go", Select).value}
      for k, _ in Flags:
        if k != "go":
          cfg[k] = self.query_one(f"#f-{k}", Input).value.strip()
      return cfg

    def restore(self, cfg):
      "Put a config back into the widgets."
      if cfg.get("go") in Goes:
        self.query_one("#f-go", Select).value = cfg["go"]
      for k, _ in Flags:
        if k != "go" and k in cfg:
          self.query_one(f"#f-{k}", Input).value = str(cfg[k])

    def action_save(self):
      def then(name):
        if name: self.notify(f"saved {save(name, self.config())}")
      self.push_screen(Ask(), then)

    def action_load(self):
      def then(name):
        if name: self.restore(load(name)); self.notify(f"loaded {name}")
      self.push_screen(Pick(), then)

    # ---- runs ---------------------------------------------------
    def reload(self, pick=0):
      "Refill the table from disk, then show one row."
      t = self.query_one("#runs", DataTable)
      t.clear()
      self.rows = runs()
      for r in self.rows:
        t.add_row(r["when"][5:16], r["cfg"].get("go", "?"),
                  f'{r["secs"]:.2f}', str(r["code"]),
                  summary(r["cfg"]))
      if self.rows:
        at = min(pick, len(self.rows) - 1)
        t.move_cursor(row=at); self.show(self.rows[at])
      else:
        self.query_one("#out", RichLog).clear()

    def show(self, r):
      "One run, in full, in the pane below."
      out = self.query_one("#out", RichLog)
      out.clear()
      out.write(f'[bold]{" ".join(r["cmd"])}[/bold]')
      out.write(f'[dim]{r["when"]}  {r["secs"]:.2f}s  '
                f'exit {r["code"]}[/dim]\n')
      out.write(r["out"] or "[dim](no output)[/dim]")
      if r["err"]: out.write(f'[red]{r["err"]}[/red]')

    @on(DataTable.RowHighlighted)
    def hop(self, e):
      if getattr(self, "rows", None) and e.cursor_row < len(self.rows):
        self.show(self.rows[e.cursor_row])

    def action_next(self):
      self.query_one("#runs", DataTable).action_cursor_down()

    def action_prev(self):
      self.query_one("#runs", DataTable).action_cursor_up()

    def action_drop(self):
      if getattr(self, "rows", None):
        at = self.query_one("#runs", DataTable).cursor_row
        Path(self.rows[at]["path"]).unlink(missing_ok=True)
        self.reload(at)

    # ---- plots --------------------------------------------------
    def action_plot(self, pix=True):
      "Plot the highlighted run's result csv, if it made one."
      if not getattr(self, "rows", None): return
      r   = self.rows[self.query_one("#runs", DataTable).cursor_row]
      csv = result(r)
      if not csv: return self.notify("that run printed no csv")
      w, h = max(40, self.size.width - 6), max(10, self.size.height - 6)
      self.push_screen(Plot(f'{csv}   {summary(r["cfg"])}',
                            plotted(csv, w, h, pix)))

    def action_ascii(self): self.action_plot(pix=False)

    # ---- running ------------------------------------------------
    @on(Button.Pressed, "#go-btn")
    def pressed(self): self.action_run()

    def action_run(self):
      cfg = self.config()
      self.notify(" ".join(command(cfg)), timeout=3)
      self.lua(cfg)

    @work(thread=True)
    def lua(self, cfg):
      "Run it off the ui thread, then show what it said."
      run(cfg)
      self.call_from_thread(self.reload)

  return Tui().run() if start else Tui

if __name__ == "__main__":
  main(sys.argv[1:])
