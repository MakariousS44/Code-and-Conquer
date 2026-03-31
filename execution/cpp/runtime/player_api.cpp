//
// Created by Emily Tew on 3/19/26.
//
#include <iostream>

void move() {
    std::cout << "[CMD] MOVE\n";
}

void turn_left() {
    std::cout << "[CMD] TURN_LEFT\n";
}

void turn_right() {
    std::cout << "[CMD] TURN_RIGHT\n";
}

void pick_object() {
    std::cout << "[CMD] PICK_OBJECT\n";
}

void put_object() {
    std::cout << "[CMD] PUT_OBJECT\n";
}

bool front_is_clear() {
    std::cout << "[CMD] FRONT_IS_CLEAR\n";
    // read back from stdin by the game engine
    // game pauses execution, checks the world state, then
    // writes 1 for clear or 0 for blocked back to the process
    int result = 0;
    std::cin >> result;
    return result == 1;
}
