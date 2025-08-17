# Old Puppetmaster architecture

make sure to read arbitrate first.

## very quick overview of the architecture

there are shards that can rename one object at a time. each shard handles different address spaces.

we treat each transaction as a "thread," because in order to fully rename all objects in a transaction, we have to interact with multiple shards potentially over multiple cycles. therefore, the number of threads that we could handle = the number of distributors = the number of aggregators (distributors and aggregators are always paired).

there are also "delete request distributors" whose jobs are to contact shards to delete all objects belonging to a transaction. they don't have paired aggregators.
there is also a single global "failed transaction handler", which is also another distributor.

each distributor and aggregator is only responsible for one transaction at a time (i.e. one thread), as mentioned earlier, therefore their implementations do not contain FIFOs. they're just FSMs with a single input register.
each distributor has an array of output ports `.distribute[i]` where `i` is the shard number it's trying to contact.

since each shard may have multiple distributors trying to contact them (`2*NumberRenamerThreads + 1`), [the access to these shards have to be arbitrated](https://github.com/CyanoKobalamyne/pmhw/blob/master/bsv/Renamer.bsv#L499-L517). in bluespec arbitate terminology, each shard is a "master" with a bunch of distributor "users."
- user index 0–`NumberRenamerThreads-1` correspond to request distributors, [next contain delete distributors, and then the final one is the failed transaction handler](https://github.com/CyanoKobalamyne/pmhw/blob/master/bsv/Renamer.bsv#L550-L560)

also, each aggregator, while responsible for only one transaction at a time, could get the results from many shards, so [access to each aggregator also needs to be arbitrated](https://github.com/CyanoKobalamyne/pmhw/blob/master/bsv/Renamer.bsv#L519-L532). this time, each aggregator is "master" and shards are users. to make sure that each aggregator only sees the relevant requests, we make use or the arbiter's ordered request-response feature, which keeps track of where the result needs to go (i.e. which aggregator). so, to be very clear, a shard also only handles one request at a time.

and of course, [the final output also needs to be arbitrated](https://github.com/CyanoKobalamyne/pmhw/blob/master/bsv/Renamer.bsv#L534-L540).

## lifecycles

### normal transaction
- first, transaction gets put in through `.rename.request.put`
- this is stored in the input buffer of size ~256.
- [whenever the renamer sees a distributor-aggregator pair free, it puts the request in](https://github.com/CyanoKobalamyne/pmhw/blob/master/bsv/Renamer.bsv#L577-L585).
- the distributor distributes. the shards rename. [the outputs are arbitrated to the one aggregator responsible for this transaction](https://github.com/CyanoKobalamyne/pmhw/blob/master/bsv/Renamer.bsv#L516).
- the aggregator eventually receives all outputs, succeeds in arbitration for the output, and made output available through `.rename.response.get`
note that responses don't necessary come out in the same order as requests.

once puppetmaster takes care of finishing that transaction, a delete request gets put in and similarly handled with no aggregation at the end.

### failed transaction

an aggregator, instead of providing a RenameResponse through `.response.get`, might provide a DeleteRequest through `.failure.get` instead. this is why there there has to be a failed transaction arbiter to take those failures and distribute to the delete distributors.

okay, actually, you don't really need failed transaction arbiter if you just allow all aggregators to route requests back to distributors, but that seem like a bad idea, especially since we don't want to spend a lot of resource on failure path anyway.

## icky stuff

this is very i/o bound. while it is possible to have many transactions in flight, only one transaction can go in or out at any given cycle. that seems problematic.

## distributor

this is an extremely serialized fsm. it iterates through all read objects first, then write objects, using `objType`, `objIndex` pair. [only one object per cycle at most](https://github.com/CyanoKobalamyne/pmhw/blob/master/bsv/Renamer.bsv#L166).

oh yea, even if there are shards available for later objects, it doesn't matter. this fsm only looks at one object at a time, in order. the distributor [considers itself done when it has iterated through all objects](https://github.com/CyanoKobalamyne/pmhw/blob/master/bsv/Renamer.bsv#L191-L194).

## response aggregator

luckily, this seems a bit more parallelized. after receiving the transaction request at the very beginning, the aggregator keeps count of how many read and write objects have been renamed. [it takes outputs directly from the shards](https://github.com/CyanoKobalamyne/pmhw/blob/master/bsv/Renamer.bsv#L531) in whatever order.

how does it know to only get the responses from the correct shards? we have to look at the shard arbiter carefully. it's not only responsible for taking in inputs from multiple users (distributors) into a shard, but it's also responsible for distributing the outputs to the correct user corresponding to each input as well. so we make use of this and hope that the outputs are routed through `users[i].response` to the correct aggregator. (but again, keep in mind that each aggregator has its own input arbiter.)

## running

so, a transaction goes from buffered, to renamed ("pending" to be put into scheduler), to scheduled (has bit set to 1, ready to be put into puppet), to running (out of the queue. currently running.)

oh btw when a transaction is scheduled or running it's just put into the tournament scheduler as "first" transaction and it takes priority because that's how the tournament scheduler works (it prioritizes the first one in order).

---

- address offset bits = 6
- object address is 64 bits
	- therefore raw object name is 58 bits
- number of shards = 256 (2&8)
- shard size = 128 (2^7)
	- therefore, total number of live objects supported = $2^7 * 2^8 = 2^{15}$
	- therefore renamed object name = 15 bits
	- object set is a `bool[2**15]`!
- max number of objects per transaction = 8
	- transaction object counter bits = 3

```

xxxxxxxx xxxxxxx   xxxxxx
^shardno ^shardkey ^offset
                   ^^^^^^^
                   ignored
```

