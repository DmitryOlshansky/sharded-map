module rewind.map;
import core.internal.spinlock;


private immutable size_t BUCKETS = 31;

size_t bucketOf(T)(auto ref T value) {
    return value.hashOf() % BUCKETS;
}

class Map(K, V) {
    struct Shard {
        V[K] map;
        SpinLock lock;
    }
    Shard[] shards;
    this() {
        shards = new Shard[BUCKETS];
    }
 
    auto opIndex(K key) {
        auto shard = &shards[bucketOf(key)];
        shard.lock.lock();
        scope(exit) shard.lock.unlock();
        return shard.map[key];
    }

    V getOrDefault(K key, V default_) {
        auto shard = &shards[bucketOf(key)];
        shard.lock.lock();
        scope(exit) shard.lock.unlock();
        auto v = key in shard.map;
        if (v) {
            return *v;
        }
        else {
            return default_;
        }
    }

    V put(K key, V value) {
        auto shard = &shards[bucketOf(key)];
        shard.lock.lock();
        scope(exit) shard.lock.unlock();
        auto p = key in shard.map;
        if (p) {
            auto old = *p;
            shard.map[key] = value;
            return old;
        }
        else {
            shard.map[key] = value;
            return V.init;
        }
    }

    ref opIndexAssign(V value, K key) {
        auto shard = &shards[bucketOf(key)];
        shard.lock.lock();
        scope(exit) shard.lock.unlock();
        shard.map[key] = value;
    }

    bool opBinaryRight(string op:"in")(K key) {
        auto shard = &shards[bucketOf(key)];
        shard.lock.lock();
        scope(exit) shard.lock.unlock();
        return (key in shard.map) != null;
    }

    void remove(K key) {
        auto shard = &shards[bucketOf(key)];
        shard.lock.lock();
        scope(exit) shard.lock.unlock();
        shard.map.remove(key);
    }

    void removeIf(K key, scope bool delegate(ref V) cond) {
        auto shard = &shards[bucketOf(key)];
        shard.lock.lock();
        scope(exit) shard.lock.unlock();
        auto value = key in shard.map;
        if (value != null && cond(*value)) {
            shard.map.remove(key);
        }
    }

    size_t length() {
        size_t len = 0;
        foreach (shard; shards) {
            len += shard.map.length;
        }
        return len;
    }

    int opApply(scope int delegate(K, V) fn) {
        foreach (ref shard; shards) {
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

unittest {
     static struct A {
        int k;
     }
     int[A] hashmap;
     auto map = new Map!(A, int);
     map[A(32)] = 2;
     assert(map[A(32)] == 2);
}

unittest {
    auto map = new Map!(string, string);
    auto key = "hello, world!";
    foreach (i; 0..key.length) {
        map[key[0..i]] = "abc";
    }
    foreach (i; 0..key.length) {
        assert(map[key[0..i]] == "abc");
    }
}

unittest {
    auto map = new Map!(string, string);
    map["abc"] = "def";
    map.removeIf("ABC", (ref string x) { return x == "def"; });
    assert(map["abc"] == "def");
    map.removeIf("abc", (ref string x) { return x == "DEF"; });
    assert(map["abc"] == "def");
    map.removeIf("abc", (ref string x) { return x == "def"; });
    assert(("abc" !in map));
}

unittest {
    auto map = new Map!(string, int);
    assert(map.put("A", 1) == 0);
    assert(map.put("A", 2) == 1);
    assert(map.getOrDefault("A", 3) == 2);
    assert(map.getOrDefault("B", 3) == 3);
}

class MultiMap(K, V) {
    struct Shard {
        SpinLock lock;
        V[][K] bucket;
    }
    Shard[] shards;

    this() {
        shards = new Shard[BUCKETS];
    }

    V[] opIndex(K key) {
        auto s = &shards[bucketOf(key)];
        s.lock.lock();
        scope(exit) s.lock.unlock();
        return s.bucket[key];
    }

    void opIndexAssign(V value, K key) {
        auto s = &shards[bucketOf(key)];
        s.lock.lock();
        scope(exit) s.lock.unlock();
        auto p = key in s.bucket;
        if (p == null) {
            s.bucket[key] = [value];
        } else {
            s.bucket[key] ~= value;
        }
    }

    void remove(K key) {
        auto s = &shards[bucketOf(key)];
        s.lock.lock();
        scope(exit) s.lock.unlock();
        s.bucket.remove(key);
    }

    size_t length() {
        size_t len = 0;
        foreach (ref shard; shards) {
            shard.lock.lock();
            scope(exit) shard.lock.unlock();
            len += shard.bucket.length;
        }
        return len;
    }

    int opApply(scope int delegate(K key, V[] value) dg) {
        foreach (ref shard; shards) {
            shard.lock.lock();
            scope(exit) shard.lock.unlock();
            foreach (k, v; shard.bucket) {
                dg(k, v);
            }
        }
        return 1;
    }
}

unittest {
    auto mm = new MultiMap!(string, int);
    mm["a"] = 2;
    mm["a"] = 3;
    assert(mm["a"] == [2,3]);
    foreach (k,v; mm) {
        assert(k == "a");
        assert(v == [2,3]);
    }
}