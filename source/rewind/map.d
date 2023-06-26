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
    
    int hashOf(int x) => x % 31;

    int hashOf(long x) => x % 31;

    int hashOf(const(char)[] str) {
        int hash = 131;
        foreach (c; str) {
            hash = hash * 31 + c;
        }
        return hash % 31;
    } 

    auto opIndex(K key) {
        auto shard = &shards[hashOf(key)];
        shard.lock.lock();
        scope(exit) shard.lock.unlock();
        return shard.map[key];
    }

    ref opIndexAssign(V value, K key) {
        auto shard = &shards[hashOf(key)];
        shard.lock.lock();
        scope(exit) shard.lock.unlock();
        shard.map[key] = value;
    }

    V* opBinaryRight(string op:"in")(K key) {
        auto shard = &shards[hashOf(key)];
        shard.lock.lock();
        scope(exit) shard.lock.unlock();
        return key in shard.map;
    }

    void remove(K key) {
        auto shard = &shards[hashOf(key)];
        shard.lock.lock();
        scope(exit) shard.lock.unlock();
        shard.map.remove(key);
    }

    size_t length() {
        size_t len = 0;
        foreach (shard; shards) {
            len += shard.map.length;
        }
        return len;
    }

    int opApply(scope int delegate(K, V) fn) {
        foreach (shard; shards) {
            shard.lock.lock();
            scope(exit) shard.lock.unlock();
            foreach (k, v; shard.map) {
                fn(k, v);
            }
        }
        return 1;
    }
}

unittest {
    auto map = new Map!(int, string);
    map[0] = "hello";
    assert(map[0] == "hello");
    assert(map.length == 1);
    foreach (k, v; map) {
        assert(k == 0);
        assert(v == "hello");
    }
    map.remove(0);
    assert(!(0 in map));
    assert(map.length == 0);
}