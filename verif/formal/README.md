# Assertion sources

This directory contains SystemVerilog Assertions used by the simulation
regression. They check CDC transaction stability, stream safety, diagnostics,
and counter behavior.

The assertions are not represented as formally proven properties: no
JasperGold, VC Formal, or equivalent formal-engine result is claimed in this
repository. A future formal upgrade should add a bounded harness, assumptions,
cover goals, and tool-generated proof reports for a selected set of properties.
