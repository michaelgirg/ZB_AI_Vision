// Class: preprocess_random_test
// Description:
//UVM randomized legal control-register test.

class preprocess_random_test extends preprocess_control_test;

    `uvm_component_utils(preprocess_random_test)

    function new(string name = "preprocess_random_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        random_control_sequence seq;

        phase.raise_objection(this);
        seq = random_control_sequence::type_id::create("random_control_seq");
        seq.start(env.agent.sequencer);
        phase.drop_objection(this);
    endtask

endclass
