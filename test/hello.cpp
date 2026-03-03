#include <iostream>
#include <string>
#include <vector>

int main() {
    std::string message = "Hello from Android NDK (C++, from source)!";
    std::vector<int> numbers = {1, 2, 3, 4, 5};

    std::cout << message << std::endl;
    std::cout << "Vector size: " << numbers.size() << std::endl;

    return 0;
}
