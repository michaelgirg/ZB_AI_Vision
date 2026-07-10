// Class: vector_stream_env

class vector_stream_env extends uvm_env;
    `uvm_component_utils(vector_stream_env)

    axi_lite_agent ctrl_agent;
    axis_stream_source_agent source_agent;
    axis_stream_sink_driver sink_driver;
    axis_stream_input_monitor input_monitor;
    axis_stream_output_monitor output_monitor;
    vector_stream_scoreboard scoreboard;
    vector_stream_coverage stream_coverage;
    vector_control_coverage control_coverage;

    function new(string name = "vector_stream_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ctrl_agent = axi_lite_agent::type_id::create("ctrl_agent", this);
        source_agent = axis_stream_source_agent::type_id::create("source_agent", this);
        sink_driver = axis_stream_sink_driver::type_id::create("sink_driver", this);
        input_monitor = axis_stream_input_monitor::type_id::create("input_monitor", this);
        output_monitor = axis_stream_output_monitor::type_id::create("output_monitor", this);
        scoreboard = vector_stream_scoreboard::type_id::create("scoreboard", this);
        stream_coverage = vector_stream_coverage::type_id::create("stream_coverage", this);
        control_coverage = vector_control_coverage::type_id::create("control_coverage", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        input_monitor.ap.connect(scoreboard.source_export);
        output_monitor.ap.connect(scoreboard.sink_export);
        output_monitor.ap.connect(stream_coverage.analysis_export);
        ctrl_agent.monitor.ap.connect(control_coverage.analysis_export);
    endfunction
endclass
