module rewind.map;
import core.internal.spinlock;

class Map(K, V) {
    struct Shard {
        V[K] map;
        SpinLock lock;
    }
    Shard[] shards;
    this() {
        shards = new Shard[31];
    }

    auto opIndex(K key) {
        auto shard = &shards[key%31];
        shard.lock.lock();
        scope(exit) shard.lock.unlock();
        return shard.map[key];
    }

    ref opIndexAssign(V value, K key) {
        auto shard = &shards[key%31];
        shard.lock.lock();
        scope(exit) shard.lock.unlock();
        shard.map[key] = value;
    }

    V* opBinaryRight(string op:"in")(K key) {
        auto shard = &shards[key%31];
        shard.lock.lock();
        scope(exit) shard.lock.unlock();
        return key in shard.map;
    }

    void remove(K key) {
        auto shard = &shards[key%31];
        shard.lock.lock();
        scope(exit) shard.lock.unlock();
        shard.map.remove(key);
    }
}

unittest {
    auto map = new Map!(int, string);
    map[0] = "hello";
    assert(map[0] == "hello");
    map.remove(0);
    assert(!(0 in map));
}