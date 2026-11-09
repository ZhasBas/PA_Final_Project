CXX ?= g++
MPICXX ?= mpicxx
CXXFLAGS ?= -O3 -std=c++17 -Wall -Wextra -Wpedantic
OPENMP ?= -fopenmp
TARGET := build/traffic_sim
SOURCE := src/traffic_sim.cpp

.PHONY: all clean mpi check
all: $(TARGET)

$(TARGET): $(SOURCE)
	@mkdir -p build
	$(CXX) $(CXXFLAGS) $(OPENMP) $< -o $@

mpi:
	@mkdir -p build
	$(MPICXX) $(CXXFLAGS) $(OPENMP) -DTRAFFIC_USE_MPI=1 $(SOURCE) -o build/traffic_sim_mpi

check: $(TARGET)
	bash tests/check_modes.sh ./$(TARGET)

clean:
	rm -rf build
