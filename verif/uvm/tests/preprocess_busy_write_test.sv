// Class: preprocess_busy_write_test
// Description:
//UVM test for writes attempted while preprocessing is busy.

class preprocess_busy_write_test extends preprocess_base_test;

    `uvm_component_utils(preprocess_busy_write_test)

    function new(string name = "preprocess_busy_write_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void configure_defaults();
        super.configure_defaults();
        input_mem_path = "generated/test_vectors/sample_000_input.mem";
        expected_mem_path = "generated/test_vectors/sample_000_threshold.mem";
        preprocess_mode = MODE_THRESHOLD;
        enable_scoreboard_compare = 1'b1;
    endfunction

    task run_phase(uvm_phase phase);
        busy_write_sequence seq;

        phase.raise_objection(this);
        seq = busy_write_sequence::type_id::create("busy_write_seq");
        seq.input_mem_path = input_mem_path;
        seq.start(env.agent.sequencer);
        phase.drop_objection(this);
    endtask

endclass
