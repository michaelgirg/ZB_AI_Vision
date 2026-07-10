// Classes: vector4_stream_test, vector4_backpressure_test, vector4_busy_write_test

class vector4_stream_test extends uvm_test;
    `uvm_component_utils(vector4_stream_test)
    vector_stream_env env;
    string expected_mem = "generated/test_vectors/sample_000_conv4.mem";

    function new(string name = "vector4_stream_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        void'($value$plusargs("EXPECTED_MEM=%s", expected_mem));
        uvm_config_db#(string)::set(this, "env.scoreboard", "expected_mem", expected_mem);
        env = vector_stream_env::type_id::create("env", this);
    endfunction

    virtual task run_vector_test(
        bit inject_busy_writes = 1'b0,
        bit use_saturation_config = 1'b0
    );
        vector_control_sequence control_sequence;
        vector_saturation_control_sequence saturation_control_sequence;
        vector_image_sequence image_sequence;
        vector_busy_write_sequence busy_sequence;
        virtual preprocess_if ctrl_vif;

        if (!uvm_config_db#(virtual preprocess_if)::get(this, "", "ctrl_vif", ctrl_vif)) begin
            `uvm_fatal("NO_CTRL_VIF", "test could not get preprocess_if")
        end

        control_sequence = vector_control_sequence::type_id::create("control_sequence");
        saturation_control_sequence =
            vector_saturation_control_sequence::type_id::create("saturation_control_sequence");
        image_sequence = vector_image_sequence::type_id::create("image_sequence");
        busy_sequence = vector_busy_write_sequence::type_id::create("busy_sequence");
        if (use_saturation_config) begin
            saturation_control_sequence.start(env.ctrl_agent.sequencer);
        end else begin
            control_sequence.start(env.ctrl_agent.sequencer);
        end

        if (inject_busy_writes) begin
            fork
                image_sequence.start(env.source_agent.sequencer);
                begin
                    repeat (150) @(posedge ctrl_vif.clk);
                    busy_sequence.start(env.ctrl_agent.sequencer);
                end
            join
        end else begin
            image_sequence.start(env.source_agent.sequencer);
        end

        fork
            begin
                wait (env.scoreboard.complete);
            end
            begin
                repeat (UVM_TIMEOUT_CYCLES) @(posedge ctrl_vif.clk);
                `uvm_fatal("TIMEOUT", "vector stream test timed out")
            end
        join_any
        disable fork;
        repeat (10) @(posedge ctrl_vif.clk);
    endtask

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        run_vector_test(1'b0, 1'b0);
        phase.drop_objection(this);
    endtask
endclass

class vector4_backpressure_test extends vector4_stream_test;
    `uvm_component_utils(vector4_backpressure_test)

    function new(string name = "vector4_backpressure_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        uvm_config_db#(int unsigned)::set(this, "env.sink_driver", "ready_low_percent", 55);
        super.build_phase(phase);
    endfunction

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        run_vector_test(1'b0, 1'b0);
        phase.drop_objection(this);
    endtask
endclass

class vector4_busy_write_test extends vector4_stream_test;
    `uvm_component_utils(vector4_busy_write_test)

    function new(string name = "vector4_busy_write_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        run_vector_test(1'b1);
        phase.drop_objection(this);
    endtask
endclass

class vector4_saturation_test extends vector4_stream_test;
    `uvm_component_utils(vector4_saturation_test)

    function new(string name = "vector4_saturation_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        uvm_config_db#(string)::set(
            this,
            "env.scoreboard",
            "expected_mem",
            "generated/test_vectors/vector4_saturation.mem"
        );
    endfunction

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        run_vector_test(1'b0, 1'b1);
        phase.drop_objection(this);
    endtask
endclass
