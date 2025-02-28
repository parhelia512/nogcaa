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
    // Grow threshold
    GROW_NUM = 4,
    GROW_DEN = 5,
    // Shrink threshold
    SHRINK_NUM = 1,
    SHRINK_DEN = 8,
    // Grow factor
    GROW_FAC = 4
}

// Growing the AA doubles it's size, so the shrink threshold must be
// Smaller than half the grow threshold to have a hysteresis
static assert(GROW_FAC * SHRINK_NUM * GROW_DEN < GROW_NUM * SHRINK_DEN);

private enum {
    // Initial load factor (for literals), mean of both thresholds
    INIT_NUM = (GROW_DEN * SHRINK_NUM + GROW_NUM * SHRINK_DEN) / 2,
    INIT_DEN = SHRINK_DEN * GROW_DEN,

    INIT_NUM_BUCKETS = 8,
    // Magic hash constants to distinguish empty, deleted, and filled buckets
    HASH_EMPTY = 0,
    HASH_DELETED = 0x1,
    HASH_FILLED_MARK = size_t(1) << 8 * size_t.sizeof - 1,

    // Specifies the maximum heap size. Default is 4 GB
    MAX_HEAP = 4_294_967_296
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
                return strlen(k1) == strlen(k2) &&
                    strcmp(k1, k2) == 0;
            else static if (isSomeString!K)
                return k1.length == k2.length && strncmp(k1.ptr, k2.ptr, k1.length) == 0;
            else
                return k1 == k2;
        }
    }
}

/// Mallocator code BEGINS

@mustuse struct Mallocator {
@nogc nothrow:

private:
    struct Fat {
        size_t length;
        byte ptr;
    }

static:
    __gshared size_t __memory;

    void* __malloc(size_t size) {
        import core.stdc.stdlib : malloc, exit, EXIT_FAILURE;

        if (!size)
            return null;
        else if (__memory + size > MAX_HEAP)
            exit(EXIT_FAILURE);

        Fat* __fat = cast(Fat*)malloc(Fat.ptr.offsetof + size);
        if (!__fat)
            return null;
        __memory += __fat.length = size; // Top up the memory counter
        foreach (i; 0 .. __fat.length)
            (&__fat.ptr)[i] = 0;

        return &__fat.ptr;
    }

    Fat* __get(void* ptr) {
        if (!ptr || cast(size_t)ptr < Fat.ptr.offsetof)
            return null;

        return cast(Fat*)(cast(size_t)ptr - Fat.ptr.offsetof);
    }

    void __free(void* ptr) {
        import core.stdc.stdlib : free;

        Fat* __fat = __get(ptr);
        if (!__fat)
            return;
        __memory -= __fat.length; // Decrease counter
        foreach (i; 0 .. __fat.length)
            (&__fat.ptr)[i] = 0; // Clear sensitive data

        return free(__fat);
    }

public:
    import std.traits : hasMember, isPointer, isDynamicArray;

    size_t heap() =>
        __memory;

    T* allocate(T, Args...)(Args args) if (is(T == struct) || is(T == union)) {
        static immutable modeinit = cast(immutable(T))T();
        T* ptr = cast(T*)__malloc(T.sizeof);
        if (!ptr)
            return null;

        memcpy(cast(void*)ptr, cast(void*)&modeinit, T.sizeof);
        static if (hasMember!(T, "__ctor"))
            ptr.__ctor(args);

        return ptr;
    }

    T[] allocate(T)(size_t length) {
        T* ptr = cast(T*)__malloc(length * T.sizeof);
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
                __free(obj_.ptr);
            else
                __free(cast(void*)obj_);
            obj_ = null;
        }
    }

    // Returns the size of the allocated memory block in bytes
    size_t __sizeof(T)(T ptr) if (isPointer!T) {
        Fat* __fat = __get(ptr);
        if (!__fat)
            return 0;

        return __fat.length;
    }

    // Returns the length of the allocated memory block in elements
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

/// Mallocator code ENDS

@mustuse struct Nogcaa(K, V, Allocator = Mallocator) {
    struct Node {
        K key;
        V val;

        alias value = val;
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
            cast(ptrdiff_t)hash < 0;
    }

private:
    Bucket[] buckets;

    int allocHtable(size_t sz) @nogc nothrow {
        auto _htable = Make.Array!Bucket(allocator, sz);
        if (!_htable)
            return -1;
        buckets = _htable;

        return 0;
    }

    int initTableIfNeeded() @nogc nothrow {
        if (buckets is null) {
            if (allocHtable(INIT_NUM_BUCKETS) != 0)
                return -1;

            firstUsed = INIT_NUM_BUCKETS;
        }

        return 0;
    }

public:
    uint firstUsed;
    uint used;
    uint deleted;

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

    int set(scope const K key, scope const V val) {
        if (initTableIfNeeded() != 0)
            return -1;

        const keyHash = calcHash(key);

        if (auto p = findSlotLookup(keyHash, key)) {
            p.entry.val = cast(V)val;
            return 0;
        }

        auto p = findSlotInsert(keyHash);

        if (p.deleted)
            --deleted;

        // Check load factor and possibly grow
        else if (++used * GROW_DEN > dim * GROW_NUM) {
            grow();
            p = findSlotInsert(keyHash);
            // assert(p.empty);
        }

        // Update search cache and allocate entry
        uint m = cast(uint)(p - buckets.ptr);
        if (m < firstUsed)
            firstUsed = m;

        p.hash = keyHash;

        if (p.deleted) {
            p.entry.key = key;
            p.entry.val = cast(V)val;
        } else {
            Node* newNode = Make.Pointer!Node(allocator);
            if (!newNode)
                return -1;

            newNode.key = key;
            newNode.val = cast(V)val;

            p.entry = newNode;
        }

        return 0;
    }

    private size_t calcHash(scope const K pkey) pure {
        // Highest bit is set to distinguish empty/deleted from filled buckets
        const hash = TKey.getHash(pkey);
        return mix(hash) | HASH_FILLED_MARK;
    }

    int resize(size_t sz) {
        auto obuckets = buckets;
        if (allocHtable(sz) != 0)
            return -1;

        foreach (ref b; obuckets[firstUsed .. $]) {
            if (b.filled)
                *findSlotInsert(b.hash) = b;
            if (b.empty || b.deleted) {
                allocator.dispose(b.entry);

                b.entry = null;
            }
        }

        firstUsed = 0;
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
            // Clear entry
            p.hash = HASH_DELETED;
            // Just mark it to be disposed

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
            return &buck.entry.val;
        return null;
    }

    /// Returning slice must be deallocated like Allocator.dispose(keys);
    // Use byKeyValue to avoid extra allocations
    K[] keys() {
        K[] ks = Make.Array!K(allocator, length);
        if (!ks)
            return null;

        size_t j;
        foreach (ref b; buckets[firstUsed .. $])
            if (b.filled)
                ks[j++] = b.entry.key;

        return ks;
    }

    /// Returning slice must be deallocated like Allocator.dispose(values);
    // Use byKeyValue to avoid extra allocations
    V[] values() {
        V[] vals = Make.Array!V(allocator, length);
        if (!vals)
            return null;

        size_t j;
        foreach (ref b; buckets[firstUsed .. $])
            if (b.filled)
                vals[j++] = b.entry.val;

        return vals;
    }

    void free() {
        foreach (ref b; buckets)
            if (b.entry)
                allocator.dispose(b.entry);

        allocator.dispose(buckets);
        deleted = used = 0;
    }

    auto copy() {
        auto newBuckets = Make.Array!Bucket(allocator, buckets.length);
        if (!newBuckets)
            return typeof(this)(); // Return empty struct

        memcpy(newBuckets.ptr, buckets.ptr, buckets.length * Bucket.sizeof);
        typeof(this) newAA = {newBuckets, firstUsed, used, deleted};
        return newAA;
    }

    int opApply(int delegate(AAPair!(K, V)) @nogc nothrow dg) {
        if (!buckets.length)
            return 0;

        int result = 0;
        foreach (ref b; buckets[firstUsed .. $]) {
            if (!b.filled)
                continue;
            result = dg(AAPair!(K, V)(&b.entry.key, &b.entry.val));
            if (result)
                break;
        }
        return 0;
    }

    struct BCAARange(alias rangeType) {
        typeof(buckets) bucks;
        size_t len;
        size_t current;

    nothrow @nogc:
        bool empty() const pure @safe =>
            len == 0;

        // Front must be called first before popFront
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
                    --len, ++current;
                    break;
                }
        }
    }

    // The following functions return an InputRange
    auto byKeyValue() {
        auto rangeType(alias T) = T;
        return BCAARange!rangeType(buckets, length, firstUsed);
    }

    auto byKey() {
        auto rangeType(alias T) = T.key;
        return BCAARange!rangeType(buckets, length, firstUsed);
    }

    auto byValue() {
        auto rangeType(alias T) = T.val;
        return BCAARange!rangeType(buckets, length, firstUsed);
    }
}

struct AAPair(K, V) {
    K* keyp;
    V* valp;
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

nothrow @nogc:
unittest {
    Nogcaa!(string, string) aa;
    scope (exit)
        aa.free;
    aa["foo"] = "bar";
    assert(aa.foo == "bar");
}

unittest {
    Nogcaa!(string, int) aa;
    scope (exit)
        aa.free;
    aa.foo = 1;
    aa.bar = 0;
    assert("foo" in aa);
    assert(aa.foo == 1);

    aa.bar = 2;
    assert("bar" in aa);
    assert(aa.bar == 2);
}

// Test "in" works for AA without allocated storage.
unittest {
    Nogcaa!(int, int) emptyMap;
    assert(0 !in emptyMap);
}

// Try to force a memory leak - issue #5
unittest {
    struct S {
        int x, y;
        string txt;
    }

    Nogcaa!(int, S) aas;
    scope (exit)
        aas.free;

    for (int i = 1024; i < 2048; i++)
        aas[i] = S(i, i * 2, "caca\0");

    aas[100] = S(10, 20, "caca\0");

    import core.stdc.stdio;

    printf(".x=%d, .y=%d, .txt.ptr=%s\n", aas[100].x, aas[100].y, aas[100].txt.ptr);

    for (int i = 1024; i < 2048; i++)
        aas.remove(i);
}
