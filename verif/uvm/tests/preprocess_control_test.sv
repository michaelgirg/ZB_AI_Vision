// Class: preprocess_control_test
// Description:
//UVM control-register coverage test.

class preprocess_control_test extends preprocess_base_test;

    `uvm_component_utils(preprocess_control_test)

    function new(string name = "preprocess_control_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void configure_defaults();
        super.configure_defaults();
        enable_scoreboard_compare = 1'b0;
    endfunction

    task run_phase(uvm_phase phase);
        control_sequence seq;

        phase.raise_objection(this);
        seq = control_sequence::type_id::create("control_seq");
        seq.start(env.agent.sequencer);
        phase.drop_objection(this);
    endtask

endclass
