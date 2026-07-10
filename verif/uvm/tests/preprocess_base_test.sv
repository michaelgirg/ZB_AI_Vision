// Class: preprocess_base_test
// Description:
//Base UVM test for the preprocessing accelerator.

class preprocess_base_test extends uvm_test;

    `uvm_component_utils(preprocess_base_test)

    preprocess_env env;

    string input_mem_path;
    string expected_mem_path;
    int preprocess_mode;
    bit enable_scoreboard_compare;

    function new(string name = "preprocess_base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void configure_defaults();
        input_mem_path = "generated/test_vectors/sample_000_input.mem";
        expected_mem_path = "generated/test_vectors/sample_000_threshold.mem";
        preprocess_mode = MODE_THRESHOLD;
        enable_scoreboard_compare = 1'b1;
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        configure_defaults();
        void'($value$plusargs("INPUT_MEM=%s", input_mem_path));
        void'($value$plusargs("EXPECTED_MEM=%s", expected_mem_path));

        uvm_config_db#(string)::set(this, "env.scoreboard", "expected_mem_path", expected_mem_path);
        uvm_config_db#(bit)::set(this, "env.scoreboard", "enable_pixel_compare", enable_scoreboard_compare);
        env = preprocess_env::type_id::create("env", this);
    endfunction

    virtual function preprocess_image_sequence create_image_sequence();
        preprocess_image_sequence seq;

        seq = preprocess_image_sequence::type_id::create("seq");
        return seq;
    endfunction

    task run_phase(uvm_phase phase);
        preprocess_image_sequence seq;

        phase.raise_objection(this);

        seq = create_image_sequence();
        seq.input_mem_path = input_mem_path;
        seq.preprocess_mode = preprocess_mode;
        seq.start(env.agent.sequencer);

        phase.drop_objection(this);
    endtask

endclass
