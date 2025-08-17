# Push--pull problem (or Bluespec Get--Put interfaces)

Consider all the ways A could transfer data to B.

Here's one, with explicit signals:

- Module A outputs a get interface
- Module B outputs a put interface
- Top level connects get to put. Easy.

A buffers the output. although, this feels quite natural. if A is a slow module, say, an FSM, it can get away with using a FIFO of size 1. A exposes a get module, so it is clearly expected to act somewhat autonomously, not dependent on B in most cases.

Dependency injection:

- Module A takes in a put interface. Calls the put internally.
- Module B outputs a put interface.
- Top level makes sure B's put is passed into A's parameters.

No buffering takes place. B has to be ready for A to be able to push data. Not the best design if throughput is important, unless there's a fifo in the top level.

Another way around:

- Module A outputs a get interface.
- Module B takes in a get interface. calls the get internally.
- Top level makes sure A's get is passed into B's parameters.

A makes progress autonomously and buffers its output because it doesn't know when its output will be taken (unless it forces `always_enabled`). A has to have data for B to be able to progress.

> Digression: module A is akin to an AXI master wrapper with `ready(m_axis_tvalid) enable(m_axis_tready)`.
> 
> Unideally, naive translation causes tready to depend on tvalid. This doesn't cause throughput problems, but can unnecessarily increase the critical path delay on the control signal.
> Seems like a necessary tradeoff to be able to interact with bluespec's inverted semantics though.
> 
> Similarly, module B is akin to an AXI slave that accepts `Get` as a parameter (not actually possible in Bluespec).
> Of course; upstream needs to make data available autonomously, unaware of when B will consume.
> (In fact, it doesn't even know when B becomes ready to consume, since B doesn't enable get until it knows there's data available.
> So in some way, B really enforces "valid must not depend on ready.")

Finally,
- Module A takes in a Put interface. Calls the put internally.
- Module B takes in a Get interface. Calls the get internally.
- Top level has a buffer, provides the put interface to A and get interface to B.

This pushes the responsibility of figuring out buffering to top level. it's also unclear whether A drives B or B drives A here. if we don't want to add any storage elements at all, we need put and get to be called together or not called somehow.

No storage elements means put is scheduled before (SB) get. (i.e. A writes for B to read in the same cycle).

But... A can't write before B decides to read.

So, this is simply impossible in bluespec semantics.

Can B signal intent to read through a separate action? i guess it can but... if it doesn't end up successfully reading, atomicity means it shouldn't have been able to signal intent to read in the first place.

So, overall, this is impossible.

This is the same situation as attempting to create a passthrough conflict-free FIFO of size 1.
