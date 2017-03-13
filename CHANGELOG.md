# 0.3.0

- Removed `buffer` and `rolling` functions

These functions did not properly use the buffers intended to mediate
the connection to a downstream consumer. This functionality is
provided by `bufferConnect` and `rollingConnect`. Thanks to Ben
Sinclair for identifying the problem.

The issue is that these are necessarily connectors between machines,
and can not be treated as modifiers of a single machine in isolation.

# 0.2.3

- GHC-8.0.1 compatibility
- Dropped support for GHC-7.8

# 0.2.0

- Fix fanout behavior (Ben SInclair)
- Make ExampleFanout a benchmark that cabal can run
