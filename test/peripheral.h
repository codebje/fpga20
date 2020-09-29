#ifndef PERIPHERAL_H
#define PERIPHERAL_H

#include "signal.h"
#include "Vfpga20.h"

class peripheral {

public:
    // Evaluate the state of the peripheral. The time is elapsed nanoseconds since power up.
    virtual void eval(Vfpga20 *module, double time) {};
};

#endif
