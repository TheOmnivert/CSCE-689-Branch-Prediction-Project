For some reason to make champsim run the Tage predictor the following changes were made to inc/ooo_cpu.h file

1) line 45: 
   from
     #include "util/lru_table.h"
   to
     #include "msl/lru_table.h"

2)  line 110:
    from
      using dib_type = champsim::lru_table<champsim::address, dib_shift, dib_shift>;
	
    to
      using dib_type = champsim::msl::lru_table<champsim::address, dib_shift, dib_shift>;
