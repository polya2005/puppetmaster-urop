# Many ways to do the same thing (coding/design decisions)

There are many ways to do the same thing. Let's make sure we're aware of all of them.

## Input wires

If there's data that's _always_ available, e.g. signal lines from the FPGA interface, then that data can be passed in as module arguments.
See <https://github.com/tchomphoochan/bluespec-synth-demo/tree/direct-inputs>.
Alternatively, that data can be passed through `Action` with `(* always_enabled, always_ready *)`.
The latter is preferred. Parameterized modules cannot be synthesized with `(* synthesize *)` guard or `-g` flag.

## Output wires

A module can output something by providing a method, exposing the output value directly or through `ActionValue`.
Its user must call the method to _pull_ the value.
Alternatively, the module can take in an interface with an `Action` method it can call with its output, essentially _pushing_ the data.
The former can be synthesized. The latter _should_ be synthesizable, but the current `bsc` compiler does not support it.

In the latter method, if the method being called does enforce some conditions, then the implicit conditions may cause other rules/methods in the module to not fire.
Meanwhile, the former approach encourages you to buffer the outputs since it's not guaranteed that the client will consume the outputs.
That said, you could probably get a similar "don't fire some rules if no one consumes the output" behavior through clever use of conditions in your method definition.
(This will probably involve `Wire#(Bool) called <- mkDWire(False)`, `called <= True` in the method, and `called` conditions in other rules you only want to execute when called.
This might introduce unwanted scheduling constraints, though.)

## There's no inheritance

Suppose you have an interface `A` and you want to create an interface `B` that extends `A`.
Since there's no inheritance, you have the choice of either composing `A` as a member of `B` or duplicating the methods of `A` in `B`.
This affects how you use an instantiation of `B` in a place that expects `A`.
In the first approach, you could simply reference the sub-interface member.
In the second appraoch, you would need to write a `toA` converter.
Generally, the first approach is preferred.

Note that this implies exporting `Get` and `Put` interfaces instead of bare `Action` or `ActionValue` methods.
Although, I'm skeptical about this corollary.
Take FIFOs for example: If FIFOs don't export `deq` and `enq` directly, we would be in a world of pain, at least pedagogically.

Although, I don't know. Maybe it isn't so bad after all if we just do everything through `mkConnection` and no ad-hoc rules/methods?
