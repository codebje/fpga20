#ifndef SIGNAL_H
#define SIGNAL_H

#include <string>

using namespace std;

enum Edge { Rising, Falling };

class signal {
    const string name;
    const Edge edge;

    signal(string name, Edge edge) : name(name), edge(edge) {};
};

#endif
