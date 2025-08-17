# Bluespec Arbiter and Arbitrate interfaces

There are actually two separate packages. `Arbitrate` and `Arbiter` both export `mkArbiter` and they are totally unrelated.

The one used in Puppetmaster is `Arbitrate`.

# `Arbitrate` package

## Use case

Suppose we have a single resource. The resource satisfies the `Server` interface; that is, the resource accepts a request and _might_ respond with something in return.
```
interface Server#(type a, type b);
    interface Put#(a) request();
    interface Get#(b) response();
endinterface
```

We want to arbitrate the access to this server across multiple users. Ideally, we should be able to provide a similar `Server` interface to each of the users, so they do not have to be aware of the underlying arbitration mechanism.

## `Arbiter` interface

The package provides an interface `Arbiter` which does this exactly.
```bsv
interface Arbiter#(numeric type ports, type request, type response);
   interface Vector#(ports, Server#(request, response)) users;
   interface Client#(request, response)                 master;
endinterface
```

It presents a `Server` interface to each of the users, so the user can make requests and receive responses.

On the other end, it presents a `Client` interface meant for the top level to connect to the shared resource (called "master"). This can be done by simply using `mkConnection`.

Of course, the interface itself doesn't tell the whole story. Let's see how one instantiates `Arbitrate`. Consider `mkArbiter`:
```
module mkArbiter#(Arbitrate#(n) arbIfc, Integer max_in_flight)(Arbiter#(n, req, resp))
   provisos(  Add#(1, _1, n)     // must have at least one user
	    , Bits#(req, sreq)   // requests must be bit representable
	    , Bits#(resp, sresp) // responses must be bit representable
	    , ArbRequestTC#(req) // supports a request with a read/write distinction
	    );
    // ...
endmodule
```

The module `mkArbiter` expects two more arguments (on top of the three parameters required by the `Arbiter` interface): an `Arbitrate#(n)` instantiation (explained later) and the number of requests to be supported.

It also has an additional provisos that `req` satisfies `ArbRequestTC` typeclass:
```
typeclass ArbRequestTC#(type a);
   function Bool isReadRequest(a x);
   function Bool isWriteRequest(a x);
endtypeclass
```
Essentially, this allows the arbiter to remember whether to route the master's response back to the client that initiated the request. Read requests have responses (i.e. read data). Write requests do _not_ have responses.

The source code of `mkArbiter` should be clear to you now. For read request, it simply keeps track of who made the read request in a central FIFO with size `max_in_flight`. If the FIFO is full, then no read requests will be accepted.

Note that all other interfacing FIFOs are simply skid buffers, _not_ `max_in_flight`! When a user makes a request, the master has to _consume_ that request first, otherwise the arbiter couldn't go ahead and grant more accesses. That is, `max_in_flight` only applies to consumed, _non-blocking_ read requests. If your master implementation does not have any mechanism for buffering inputs, make sure to add some FIFOs.

## `Arbitrate` interface

`Arbitrate` is an interface for _deciding_ which one of the `size` clients should be "granted" the permission to use the shared resource. It doesn't route any actual data. Its only job is to create the `grant` vector. (Why `vector` rather than an index? Because it's a bit more easy to `map` acrosse vector of clients that way.)

```bsv
interface Arbitrate#(numeric type size);
   method    Action              request(Vector#(size, Bool) req);
   method    Vector#(size, Bool) grant;
endinterface
```

There are many implementations for `Arbitrate`. The most obvious one is `mkRoundRobin` which can be instantiated with no arguments. There's also `mkFixedPriority`, also with no arguments, which prioritizes lower indices first.

So, to summarize, in order to use `Arbiter`, you must create `Arbitrate` first, pass it into `mkArbiter`, then finally make all the necessary connections.

## `Arbiter` package

Similar to `Arbitrate` package but without a separate `Arbitrate` interface thing. Somehow manages to still be more awkward to use than the `Arbitrate` package. Therefore, just ignore this one.
