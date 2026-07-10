// Class: preprocess_sobel_test
// Description:
//UVM Sobel preprocessing test.

class preprocess_sobel_test extends preprocess_base_test;

    `uvm_component_utils(preprocess_sobel_test)

    function new(string name = "preprocess_sobel_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void configure_defaults();
        super.configure_defaults();
        input_mem_path = "generated/test_vectors/sample_000_input.mem";
        expected_mem_path = "generated/test_vectors/sample_000_sobel.mem";
        preprocess_mode = MODE_SOBEL;
        enable_scoreboard_compare = 1'b1;
    endfunction

    function preprocess_image_sequence create_image_sequence();
        sobel_sequence seq;

        seq = sobel_sequence::type_id::create("sobel_seq");
        return seq;
    endfunction

endclass
