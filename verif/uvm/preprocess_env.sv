// Class: preprocess_env
// Description:
//UVM environment for the AXI-Lite preprocessing accelerator.

class preprocess_env extends uvm_env;

    `uvm_component_utils(preprocess_env)

    axi_lite_agent agent;
    preprocess_scoreboard_uvm scoreboard;
    preprocess_coverage_uvm coverage;

    function new(string name = "preprocess_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        agent = axi_lite_agent::type_id::create("agent", this);
        scoreboard = preprocess_scoreboard_uvm::type_id::create("scoreboard", this);
        coverage = preprocess_coverage_uvm::type_id::create("coverage", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        agent.monitor.ap.connect(scoreboard.analysis_export);
        agent.monitor.ap.connect(coverage.analysis_export);
    endfunction

endclass
