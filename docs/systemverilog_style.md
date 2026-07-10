# SystemVerilog Style Notes

These are the local rules for RTL and testbenches in this project. They are based on the ARC-Lab-UF SystemVerilog tutorial and Intel training modules referenced by the project:

- https://github.com/ARC-Lab-UF/sv-tutorial
- https://github.com/ARC-Lab-UF/intel-training-modules

## RTL Rules

- Design the circuit first, then write the code.
- Keep the first preprocessing core simple: combinational threshold logic plus one output register stage.
- Use `logic` for SystemVerilog signals.
- Use `always_ff` for registers.
- Use nonblocking assignments in sequential logic.
- Keep reset behavior explicit.
- Keep datapath modules independent from AXI/BRAM wrappers until standalone simulation passes.
- Avoid unnecessary resets on large datapath arrays later, because high-fanout reset can hurt timing.

## Testbench Rules

- Keep separate responsibilities: clock generation, stimulus, reference model, output checking, and timeout.
- Drive DUT inputs with nonblocking assignments on clock boundaries to avoid race-condition ambiguity.
- Check outputs on clock boundaries instead of using tiny delays after a clock edge.
- Use `===` and `!==` in testbenches so unknown values cannot hide bugs.
- Use a small function for the golden model when the expected behavior is simple.
- Fail loudly with `$fatal` when outputs mismatch.
- Add a timeout so a stuck DUT does not run forever.

## Current Milestone

Milestone 3 now uses the standalone threshold core, full-image engine, buffered
wrapper, and register-controlled wrapper. Full AXI-Lite packaging comes after
the register flow passes against Python-generated `.mem` files.

## Timing-Driven Engine Rules

For the next image engine, follow `docs/timing_engine_notes.md`.

Key rules:

- parameterize image size and pixels per cycle
- use countdown counters where possible
- keep datapath valid-driven instead of reset-heavy
- avoid high-fanout enables inside the pixel pipeline
- account for memory read latency with valid pipelines
- keep the memory wrapper separate from the processing engine
