// Class: preprocess_reset_test
// Description:
//UVM test for reset during idle and active preprocessing.

class preprocess_reset_test extends preprocess_base_test;

    `uvm_component_utils(preprocess_reset_test)

    virtual preprocess_if vif;

    function new(string name = "preprocess_reset_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void configure_defaults();
        super.configure_defaults();
        input_mem_path = "generated/test_vectors/sample_000_input.mem";
        expected_mem_path = "generated/test_vectors/sample_000_threshold.mem";
        preprocess_mode = MODE_THRESHOLD;
        enable_scoreboard_compare = 1'b1;
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(virtual preprocess_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NO_VIF", "preprocess_reset_test could not get preprocess_if")
        end
    endfunction

    task run_phase(uvm_phase phase);
        reset_sequence seq;

        phase.raise_objection(this);
        seq = reset_sequence::type_id::create("reset_seq");
        seq.input_mem_path = input_mem_path;
        seq.vif = vif;
        seq.start(env.agent.sequencer);
        phase.drop_objection(this);
    endtask

endclass
