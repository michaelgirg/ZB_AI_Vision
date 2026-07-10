// Class: sobel_sequence
// Description:
//UVM image sequence configured for Sobel preprocessing.

class sobel_sequence extends preprocess_image_sequence;

    `uvm_object_utils(sobel_sequence)

    function new(string name = "sobel_sequence");
        super.new(name);
        preprocess_mode = MODE_SOBEL;
    endfunction

endclass
