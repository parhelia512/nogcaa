/**
 * Simple associative array implementation for D (-betterC, @nogc)
 *
 * The author of the original implementation: Martin Nowak
 *
 * Copyright:
 *  Copyright (c) 2020, Ferhat Kurtulmuş
 *  Copyright (c) 2025, Alexander Chepkov
 *
 *  License:
 *    $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 *
 * Simplified betterC port of druntime/blob/master/src/rt/aaA.d
 */

module nogcaa;

version (LDC) {
    version (D_BetterC) {
        pragma(LDC_no_moduleinfo);
    }
}

import core.stdc.string : strlen, strcpy, strncmp, memcpy, memset;
import core.attribute;

version (Windows) extern (C) private void* _memsetn(scope void* s, int c, size_t n) @nogc nothrow pure =>
    memset(s, c, n);

version (Posix) {
@nogc nothrow pure:
    extern (C) private void* _memset128ii(scope void* s, int c, size_t n) =>
        memset(s, c, n);

    extern (C) void _d_dso_registry() =>
        cast(void)null;
}

private enum {
    /* Grow threshold */
    GROW_NUM = 4,
    GROW_DEN = 5,
    /* Shrink threshold */
    SHRINK_NUM = 1,
    SHRINK_DEN = 8,
    /* Grow factor */
    GROW_FAC = 4
}

/* Growing the AA doubles it's size, so the shrink threshold must be */
/* Smaller than half the grow threshold to have a hysteresis */
static assert(GROW_FAC * SHRINK_NUM * GROW_DEN < GROW_NUM * SHRINK_DEN);

private enum {
    /* Initial load factor (for literals), mean of both thresholds */
    INIT_NUM = (GROW_DEN * SHRINK_NUM + GROW_NUM * SHRINK_DEN) / 2,
    INIT_DEN = SHRINK_DEN * GROW_DEN,

    INIT_NUM_BUCKETS = 8,
    /* Magic hash constants to distinguish empty, deleted, and filled buckets */
    HASH_EMPTY = 0,
    HASH_DELETED = 1,
    HASH_FILLED = size_t(1) << (8 * size_t.sizeof - 1)
}

static if (!__traits(compiles, MAX_HEAP)) {
    enum MAX_HEAP = 4_294_967_296;
}

private {
    alias hash_t = size_t;

    enum isSomeString(T) = is(immutable T == immutable C[], C) &&
        (is(C == char) || is(C == wchar) || is(C == dchar));

    template KeyType(K) {
        alias Key = K;

    @nogc nothrow pure:
        hash_t getHash(scope const Key key) @safe =>
            key.hashOf;

        bool equals(scope const Key k1, scope const Key k2) {
            static if (is(K == const(char)*))
                return strlen(k1) == strlen(k2) && strcmp(k1, k2) == 0;
            else static if (isSomeString!K)
                return k1.length == k2.length && strncmp(k1.ptr, k2.ptr, k1.length) == 0;
            else
                return k1 == k2;
        }
    }
}

@mustuse struct Mallocator {
@nogc nothrow:

private:
    struct Fat {
    align(byte.sizeof):
        size_t length;
        byte ptr;
    }

    static if (size_t.sizeof == uint.sizeof) {
        static assert(Fat.sizeof == 5);
    } else static if (size_t.sizeof == ulong.sizeof) {
        static assert(Fat.sizeof == 9);
    } else
        static assert(false, "Unsupported OS bitness");

static:
        __gshared size_t _Allocated_memory;

    void* malloc(size_t size) {
        static import core.stdc.stdlib;

        if (!size || size > MAX_HEAP || _Allocated_memory > MAX_HEAP - size)
            return null;

        size_t header = Fat.ptr.offsetof;
        if (size > size_t.max - header)
            return null;

        Fat* _Fat = cast(Fat*)core.stdc.stdlib.calloc(header + size, byte.sizeof);
        if (!_Fat)
            return null;

        _Allocated_memory += _Fat.length = size;

        return &_Fat.ptr;
    }

    Fat* get(void* ptr) {
        import core.stdc.stdint : uintptr_t;

        if (!ptr)
            return null;

        return cast(Fat*)(cast(uintptr_t)ptr - Fat.ptr.offsetof);
    }

    void free(void* ptr) {
        static import core.stdc.stdlib;

        Fat* _Fat = get(ptr);
        if (!_Fat)
            return;

        _Allocated_memory = (_Allocated_memory >= _Fat.length) ? _Allocated_memory - _Fat.length : 0;
        foreach (i; 0 .. _Fat.length)
            (&_Fat.ptr)[i] = 0;

        return core.stdc.stdlib.free(_Fat);
    }

    size_t __sizeof(T)(T ptr) if (isPointer!T) {
        Fat* _Fat = get(ptr);
        if (!_Fat)
            return 0;

        return _Fat.length;
    }

public:
    import std.traits : hasMember, isPointer, isDynamicArray;

    @property size_t heap() =>
        _Allocated_memory;

    T* allocate(T, Args...)(Args args) if (is(T == struct) || is(T == union)) {
        static immutable modeinit = cast(immutable(T))T();
        T* ptr = cast(T*)malloc(T.sizeof);
        if (!ptr)
            return null;

        memcpy(cast(void*)ptr, cast(void*)&modeinit, T.sizeof);
        static if (hasMember!(T, "__ctor"))
            ptr.__ctor(args);

        return ptr;
    }

    T[] allocate(T)(size_t length) {
        T* ptr = cast(T*)malloc(length * T.sizeof);
        if (!ptr)
            return null;

        return ptr[0 .. length];
    }

    void deallocate(T, bool doFree = true)(ref T obj_) {
        if (!obj_)
            return;

        static if (hasMember!(T, "__dtor"))
            obj_.__dtor();
        else static if (hasMember!(T, "__xdtor"))
            obj_.__xdtor();

        static if (doFree) {
            static if (isDynamicArray!T)
                free(obj_.ptr);
            else
                free(cast(void*)obj_);
            obj_ = null;
        }
    }

    size_t length(T)(T ptr) if (isPointer!T) =>
        __sizeof(ptr) / (*T).sizeof;

    alias dispose = deallocate;

    Mallocator instance;
}

@mustuse struct Make {
@nogc nothrow static:
    T[] Array(T, Allocator)(auto ref Allocator mallocator, size_t length) =>
        cast(T[])mallocator.allocate!byte(length * T.sizeof);

    T* Pointer(T, Allocator)(auto ref Allocator mallocator) =>
        cast(T*)mallocator.allocate!byte(T.sizeof).ptr;
}

@mustuse struct Nogcaa(K, V, Allocator = Mallocator) {
    struct Node {
        K key;
        V value;
    }

    struct Bucket {
    private pure nothrow @nogc @safe:
        size_t hash;
        Node* entry;

        @property bool empty() const =>
            hash == HASH_EMPTY;

        @property bool deleted() const =>
            hash == HASH_DELETED;

        @property bool filled() const =>
            !!(hash & HASH_FILLED);
    }

private:
    Bucket[] buckets;

    int allocHtable(size_t sz) @nogc nothrow {
        Bucket[] _htable = Make.Array!Bucket(allocator, sz);
        if (!_htable)
            return -1;
        buckets = _htable;

        return 0;
    }

    int initTableIfNeeded() @nogc nothrow {
        if (buckets is null)
            if (allocHtable(INIT_NUM_BUCKETS) != 0)
                return -1;

        return 0;
    }

public:
    size_t used, deleted;

    alias TKey = KeyType!K;

    alias allocator = Allocator.instance;

@nogc nothrow:
    @property pure @safe {
        size_t length() const
        in (used >= deleted) =>
            used - deleted;

        size_t dim() const =>
            buckets.length;

        size_t mask() const =>
            dim - 1;
    }

    inout(Bucket)* findSlotInsert(size_t hash) inout pure {
        for (size_t i = hash & mask, j = 1;; ++j) {
            if (!buckets[i].filled)
                return &buckets[i];
            i = (i + j) & mask;
        }
    }

    inout(Bucket)* findSlotLookup(size_t hash, scope const K key) inout {
        for (size_t i = hash & mask, j = 1;; ++j) {
            if (buckets[i].hash == hash && TKey.equals(key, buckets[i].entry.key))
                return &buckets[i];

            if (buckets[i].empty)
                return null;
            i = (i + j) & mask;
        }
    }

    int set(scope const K key, scope const V value) {
        if (initTableIfNeeded() != 0)
            return -1;

        const keyHash = calcHash(key);

        if (auto p = findSlotLookup(keyHash, key)) {
            p.entry.value = cast(V)value;
            return 0;
        }

        auto p = findSlotInsert(keyHash);

        if (p.deleted)
            --deleted;
        else if (++used * GROW_DEN > dim * GROW_NUM)
            grow(), p = findSlotInsert(keyHash);

        if (p.deleted) {
            p.entry.key = key;
            p.entry.value = cast(V)value;
        } else {
            Node* newNode = Make.Pointer!Node(allocator);
            if (!newNode)
                return -1;

            newNode.key = key;
            newNode.value = cast(V)value;

            p.entry = newNode;
        }

        p.hash = keyHash;

        return 0;
    }

    private size_t calcHash(scope const K pkey) pure {
        const hash = TKey.getHash(pkey);
        return mix(hash) | HASH_FILLED;
    }

    int resize(size_t sz) {
        auto obuckets = buckets;
        if (allocHtable(sz) != 0)
            return -1;

        foreach (ref b; obuckets[0 .. $]) {
            if (b.filled)
                *findSlotInsert(b.hash) = b;
            else if (b.empty || b.deleted) {
                allocator.dispose(b.entry);

                b.entry = null;
            }
        }

        used -= deleted;
        deleted = 0;

        allocator.dispose(obuckets);

        return 0;
    }

    int rehash() {
        if (length)
            return resize(nextpow2(INIT_DEN * length / INIT_NUM));
        return 0;
    }

    int grow() =>
        resize(length * SHRINK_DEN < GROW_FAC * dim * SHRINK_NUM ? dim : GROW_FAC * dim);

    int shrink() {
        if (dim > INIT_NUM_BUCKETS)
            return resize(dim / GROW_FAC);
        return 0;
    }

    bool remove(scope const K key) {
        if (!length)
            return false;

        const hash = calcHash(key);
        if (auto p = findSlotLookup(hash, key)) {
            p.hash = HASH_DELETED;

            ++deleted;
            if (length * SHRINK_DEN < dim * SHRINK_NUM)
                if (shrink() != 0)
                    return false;

            return true;
        }
        return false;
    }

    V get(scope const K key) {
        if (auto ret = key in this)
            return *ret;
        return V.init;
    }

    alias opIndex = get;

    int opIndexAssign(scope const V value, scope const K key) =>
        set(key, value);

    static if (isSomeString!K)
        @property {
            auto opDispatch(K key)() =>
                opIndex(key);

            auto opDispatch(K key)(scope const V value) =>
                opIndexAssign(value, key);
        }

    V* opBinaryRight(string op : "in")(scope const K key) {
        if (!length)
            return null;

        const keyHash = calcHash(key);
        if (auto buck = findSlotLookup(keyHash, key))
            return &buck.entry.value;
        return null;
    }

    /* Returning slice must be deallocated like Allocator.dispose(keys); */
    /* Use byKeyValue to avoid extra allocations */
    K[] keys() {
        K[] ks = Make.Array!K(allocator, length);
        if (!ks)
            return null;

        size_t j;
        foreach (ref b; buckets[0 .. $])
            if (b.filled)
                ks[j++] = b.entry.key;

        return ks;
    }

    /* Returning slice must be deallocated like Allocator.dispose(values); */
    /* Use byKeyValue to avoid extra allocations */
    V[] values() {
        V[] values = Make.Array!V(allocator, length);
        if (!values)
            return null;

        size_t j = 0;
        foreach (ref b; buckets[0 .. $])
            if (b.filled)
                values[j++] = b.entry.value;

        return values;
    }

    void free() {
        foreach (ref b; buckets)
            if (b.entry)
                allocator.dispose(b.entry);

        allocator.dispose(buckets);
        deleted = used = 0;
    }

    auto copy() {
        typeof(this) newAA;
        foreach (pairs; this.byKeyValue())
            newAA[pairs.key] = pairs.value;
        return newAA;
    }

    int opApply(int delegate(AAPair!(K, V)) @nogc nothrow dg) {
        if (!buckets.length)
            return 0;

        int result = 0;
        foreach (ref b; buckets[0 .. $]) {
            if (!b.filled)
                continue;
            result = dg(AAPair!(K, V)(&b.entry.key, &b.entry.value));
            if (result)
                break;
        }
        return 0;
    }

    struct NogcaaRange(alias rangeType) {
        typeof(buckets) bucks;
        size_t length, current = 0;

    nothrow @nogc:
        bool empty() const pure @safe =>
            this.length == 0;

        /* Front must be called first before popFront */
        auto front() {
            while (bucks[current].hash <= 0)
                ++current;

            auto entry = bucks[current].entry;
            mixin rangeType!entry;
            return rangeType;
        }

        void popFront() {
            foreach (ref b; bucks[current .. $])
                if (!b.empty) {
                    --this.length, ++current;
                    break;
                }
        }
    }

    /* The following functions return an InputRange */
    auto byKeyValue() {
        auto rangeType(alias T) = T;
        return NogcaaRange!rangeType(buckets, length);
    }

    auto byKey() {
        auto rangeType(alias T) = T.key;
        return NogcaaRange!rangeType(buckets, length);
    }

    auto byValue() {
        auto rangeType(alias T) = T.value;
        return NogcaaRange!rangeType(buckets, length);
    }
}

struct AAPair(K, V) {
    K* pkey;
    V* pvalue;
}

private size_t nextpow2(size_t n) pure nothrow @nogc {
    import core.bitop : bsr;

    if (!n)
        return 1;

    const isPowerOf2 = !((n - 1) & n);
    return 1 << (bsr(n) + !isPowerOf2);
}

private size_t mix(size_t h) @safe pure nothrow @nogc {
    enum m = 0x5BD1E995;
    h ^= h >> 13;
    h *= m;
    h ^= h >> 15;
    return h;
}
