// Class: preprocess_threshold_test
// Description:
//UVM threshold preprocessing test.

class preprocess_threshold_test extends preprocess_base_test;

    `uvm_component_utils(preprocess_threshold_test)

    function new(string name = "preprocess_threshold_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void configure_defaults();
        super.configure_defaults();
        input_mem_path = "generated/test_vectors/sample_000_input.mem";
        expected_mem_path = "generated/test_vectors/sample_000_threshold.mem";
        preprocess_mode = MODE_THRESHOLD;
        enable_scoreboard_compare = 1'b1;
    endfunction

    function preprocess_image_sequence create_image_sequence();
        threshold_sequence seq;

        seq = threshold_sequence::type_id::create("threshold_seq");
        return seq;
    endfunction

endclass
