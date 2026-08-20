# LEP — power line drafting for AutoCAD

**Русская версия: [README.ru.md](README.ru.md)**

A set of AutoLISP modules that automate drafting of overhead and underground
power lines in AutoCAD 2025 (macOS and Windows): route tracing, pole placement,
span cutting, cable trenches, transformer substations and a bill of materials
exported to CSV.

Built for a real contractor's workflow — the kind of drawing you produce when
connecting a customer to the grid: a cadastral map screenshot as an underlay,
a traced route on top of it, poles along the route, spans between them, and a
report at the end.

```
LEP-SCALE  →  LEP-ROUTE  →  LEP-POLE  →  LEP-SPAN  →  LEP-END  →  LEP-REPORT
calibrate     trace the     place the    wire the     terminate   export the
the underlay  route         poles        spans        the line    bill
```

## What it does

- **Scale calibration** — pick two points with a known real distance, and one
  AutoCAD unit becomes one metre. The underlay is moved to its own layer and
  pushed to the back of the draw order.
- **Route tracing** — a polyline on a service layer with a voltage class
  (10 kV / 6 kV / 0.4 kV) stored in XDATA. Every route gets its own ID, so a
  single drawing can hold several lines to different customers.
- **Pole placement** — click near the route and the point is projected onto it;
  from the second pole on you can type the distance from the previous one with
  a sign instead of clicking. Pole type, status (planned or existing) and a
  two-line label come from the route's voltage class. Anchor and corner types
  automatically get their struts drawn.
- **Spans** — wire brand and cross-section per span, with the length taken from
  the geometry, plus slack allowances by norm and pipes for horizontal
  directional drilling.
- **Cable sections** — trenches with dimensions per leg, cable kiosks, and a
  marker for the point where the laying method changes.
- **Substations** — pole-mounted, ground-level and pad-mounted transformers
  (МТП / КТП / СТП) with labels.
- **GPS points** — import from GeoJSON and draw as reference circles.
- **Bill of materials** — `LEP-REPORT` walks the drawing and writes a CSV with
  poles by stand type, spans by wire brand, and cable lengths.

## Install

1. Put the whole folder anywhere on disk.
2. Add that folder to AutoCAD's Support File Search Path
   (*Options → Files → Support File Search Path*). One-time setup per machine.
3. Open any drawing. `acaddoc.lsp` loads `LEP-START.LSP` automatically and
   creates all project layers.

To reload after editing the code without reopening the drawing: `APPLOAD` →
`LEP-START.LSP`.

## Commands

| Command | What it does |
|---|---|
| `LEP-SCALE` | calibrate the underlay scale by two points |
| `LEP-ROUTE` | trace the route, pick the voltage class |
| `LEP-ROUTEVIS` | show/hide the service route line |
| `LEP-POLE` | place poles along the route in a loop |
| `LEP-POLE-ALONE` | place a single pole not bound to any route |
| `LEP-POLE-MOVE` / `LEP-POLE-DELETE` | move or delete a pole with its label and struts |
| `LEP-SPAN` | wire the spans between poles |
| `LEP-SPAN-REPAIR` | rebuild span data after manual edits |
| `LEP-SPAN-WIRE` | change the wire/cable brand on spans already drawn |
| `LEP-END` | terminate the line — substation, meter box, kiosk |
| `LEP-GEOPOINTS-EXTRACT` / `-DRAW` / `-CLEAR` | GPS points from GeoJSON |
| `LEP-REPORT` | export the bill of materials to CSV |
| `LEP-TEST-SCENE` | generate a test drawing to try things out |

## Repository layout

```
acaddoc.lsp        AutoCAD autoloader — pulls in LEP-START on any drawing
LEP-START.LSP      loads every module, registers the trusted path
LEP-SETUP.LSP      creates all project layers and the text style
LEP-CONFIG.LSP     every tunable: colours, layers, pole types, wire brands
LEP-DATA.LSP       XDATA read/write — the drawing itself is the database
LEP-ROUTE.LSP      route tracing
LEP-POLE.LSP       pole placement, LEP-POLE.DCL — the optional dialog
LEP-SPAN.LSP       spans and wires
LEP-END.LSP        line termination
LEP-REPORT.LSP     bill of materials
LEP-*SYM.LSP       symbols: poles, transformers, kiosks, HDD pits
LEP-GEOPOINTS.LSP  GeoJSON import
LEP-POLYLINE.LSP   polyline geometry helpers
LEP-UTILS.LSP      shared helpers
LEP-SCALE.LSP      scale calibration
LEP-TEST-SCENE.LSP test drawing generator
```

There is no database and no external storage: everything the program knows
lives in the drawing itself, in XDATA attached to entities.

## A note on the comments

The code is heavily commented, and deliberately so. The author is not a
programmer, and the comments explain not only *what* a function does but *why*
it does it that way — which AutoCAD behaviour forced the decision, what broke
before, what was tried and rejected. That is the point of them, not bloat.

Detailed documentation, the full change history and known rough edges live in
[LEP-README.md](LEP-README.md) (in Russian). Whatever the program still does by
guesswork, pending confirmation from an electrical engineer, is tracked
separately in [LEP-QUESTIONS.md](LEP-QUESTIONS.md) (also in Russian).

## Contact

Licensing, questions, bug reports: **vdovikov@me.com** or an issue here.

## Status

~12 400 lines of AutoLISP, in daily production use. Known rough edges are
listed at the top of [LEP-README.md](LEP-README.md) — the most important one
is that strut rotation on two- and three-stand poles is still an approximation.

## License

**Source-available, not open source.** You may read and study the code; any
use — including running it, modifying it or producing drawings with it —
requires a written licence from the author. Commercial and non-commercial
licences are available: write to **vdovikov@me.com** describing how you intend
to use it, or open an issue.

Full terms: [LICENSE](LICENSE) (English) · [LICENSE.ru](LICENSE.ru) (Russian).
