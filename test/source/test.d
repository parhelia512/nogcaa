module test;

import nogcaa;
import nogcsw;
import core.stdc.stdio;

extern (C) void main() @nogc {
    printf("Mallocator test\n");
    auto memory = Mallocator.allocate!int(1024);
    scope (exit) {
        Mallocator.instance.deallocate(memory);
        printf("Heap after deallocation: %zu\n", Mallocator.instance.heap);
        assert(Mallocator.instance.heap == 0);
    }

    printf("Heap after allocation: %zu\n", Mallocator.instance.heap);
    printf("[Array] length: %zu\n", memory.length);
    printf("Pointer length: %zu\n", Mallocator.length(memory.ptr));

    assert(memory.length == Mallocator.length(memory.ptr));

    auto sw = StopWatch(true);
    Nogcaa!(int, int) aa0;
    scope (exit) {
        aa0.free;
        printf("Elapsed time: %lf, heap after aa0.free: %zu \n",
            cast(double)sw.elapsed!"usecs"() / 1_000_000, Mallocator.instance.heap);
    }

    foreach (i; 0 .. 1_000_000)
        aa0[i] = i;
    printf("Heap of aa0[%zu]: %zu\n", aa0.length, Mallocator.instance.heap);

    foreach (i; 2_000 .. 1_000_000)
        aa0.remove(i);
    printf("aa0[1_000]: %d\n", aa0[1_000]);

    printf("Elapsed time: %lf, heap: %zu \n", cast(double)sw.elapsed!"usecs"() / 1_000_000, Mallocator
            .instance.heap);

    Nogcaa!(string, string) aa1;
    scope (exit) {
        printf("Heap before aa1.free(): %zu\n", Mallocator.instance.heap);
        aa1.free;
        printf("After: %zu\n", Mallocator.instance.heap);
    }

    aa1["Stevie"] = "Ray Vaughan";
    aa1["Asım Can"] = "Gündüz";
    aa1["Dan"] = "Patlansky";
    aa1["İlter"] = "Kurcala";
    aa1["Кириллица"] = "Тоже работает";
    aa1.Ferhat = "Kurtulmuş";

    foreach (pair; aa1)
        printf("%s -> %s\n", (*pair.pkey).ptr, (*pair.pvalue).ptr);

    if (auto pvalue = "Dan" in aa1)
        printf("Dan %s exists!\n", (*pvalue).ptr);
    else
        printf("Dan does not exist!\n");

    assert(aa1.remove("Ferhat") == true);
    assert(aa1["Ferhat"] == null);
    assert(aa1.remove("Foe") == false);
    assert(aa1["İlter"] == "Kurcala");

    aa1.rehash();

    printf("%s\n", aa1["Stevie"].ptr);
    printf("%s\n", aa1["Asım Can"].ptr);
    printf("%s\n", aa1.Dan.ptr);
    printf("%s\n", aa1["Ferhat"].ptr);

    auto keys = aa1.keys;
    scope (exit)
        Mallocator.instance.dispose(keys);
    foreach (key; keys)
        printf("%s -> %s\n", key.ptr, aa1[key].ptr);

    struct Guitar {
        string brand;
    }

    Nogcaa!(int, Guitar) guitars;
    scope (exit)
        guitars.free;

    guitars[0] = Guitar("Fender");
    guitars[3] = Guitar("Gibson");
    guitars[356] = Guitar("Stagg");

    assert(guitars[3].brand == "Gibson");

    printf("%s\n", guitars[356].brand.ptr);

    if (auto valPtr = 3 in guitars)
        printf("%s\n", (*valPtr).brand.ptr);

    foreach (pairs; guitars.byKeyValue())
        printf("Guitar iter: %d, %s\n", pairs.key, pairs.value.brand.ptr);

    Nogcaa!(int, int) emptyMap;
    assert(0 !in emptyMap);
    foreach (pairs; emptyMap.byKeyValue())
        assert(0, "You are not allowed to be here");

    struct S {
        int x;
        int y;
        string txt;
    }

    Nogcaa!(int, S) aas;
    scope (exit) {
        printf("Heap before aas.free(): %zu\n", Mallocator.instance.heap);
        aas.free;
        printf("After: %zu\n", Mallocator.instance.heap);
    }

    for (size_t j = 0; j < 100; j++) {
        for (int i = 0; i < 100_000; i++)
            aas[i] = S(i, i * 2, "caca");

        aas[100] = S(10, 20, "caca");

        for (int i = 1_000; i < 90_000; i++)
            aas.remove(i);
    }

    struct Small {
        int a;
        short b;
    }

    printf("Mallocator struct allocate test\n");
    auto p = Mallocator.allocate!Small();
    scope (exit) {
        Mallocator.instance.deallocate(p);
        printf("Mallocator heap after struct free: %zu\n", Mallocator.instance.heap);
    }

    p.a = 42;
    p.b = 7;
    assert(p.a == 42);
    assert(p.b == 7);

    auto arr = Mallocator.allocate!int(16);
    assert(arr.length == 16);
    assert(Mallocator.length(arr.ptr) == 16);
    arr[0] = -1;
    arr[$ - 1] = 12_345;

    printf("Array first: %d last: %d length: %zu\n", arr[0], arr[$ - 1], arr.length);
    Mallocator.instance.deallocate(arr);

    Nogcaa!(int, int) map;
    scope (exit) {
        map.free;
        printf("map heap after free: %zu\n", Mallocator.instance.heap);
    }

    foreach (i; 0 .. 1024) {
        map[i] = i * 10;
    }
    assert(map.length == 1024);

    assert(map[0] == 0);
    assert(map[100] == 1000);

    foreach (i; 100 .. 200) {
        assert(map.remove(i));
    }
    assert(map.length == 1024 - 100);
    assert(map[150] == 0);

    assert(!map.remove(-1));

    map.rehash();
    assert(map.length == 1024 - 100);

    foreach (i; 200 .. 1024)
        map.remove(i);

    foreach (i; 0 .. 100)
        assert(map[i] == i * 10);

    Nogcaa!(string, string) sMap;
    scope (exit)
        sMap.free;

    sMap["en"] = "English";
    sMap["tr"] = "Türkçe";
    sMap["ru"] = "Русский";
    sMap["zh"] = "中文";

    assert(sMap["en"] == "English");
    assert(sMap.en == "English");
    assert(sMap["tr"] == "Türkçe");

    auto smkeys = sMap.keys;
    scope (exit)
        Mallocator.instance.dispose(smkeys);
    assert(smkeys.length == sMap.length);

    auto vals = sMap.values;
    scope (exit)
        Mallocator.instance.dispose(vals);
    assert(vals.length == sMap.length);

    auto copied = sMap.copy();

    foreach (pairs; copied.byKeyValue())
        printf("Copied: %s, %s\n", pairs.key.ptr, pairs.value.ptr);

    import core.stdc.string : strncmp;

    sMap.free;
    assert(copied.length == smkeys.length);
    assert(copied["en"] == "English");
    assert(copied.en == "English");
    assert(copied["tr"] == "Türkçe");
    assert(copied.ru == "Русский");
    copied.free;

    Nogcaa!(int, int) irangeMap;
    scope (exit)
        irangeMap.free;

    foreach (i; 0 .. 32)
        irangeMap[i] = i * 32;

    size_t countK = 0;
    foreach (k; irangeMap.byKey())
        ++countK;

    assert(countK == irangeMap.length);

    size_t countV = 0;
    foreach (v; irangeMap.byValue())
        ++countV;

    assert(countV == irangeMap.length);

    size_t countKV = 0;
    foreach (kv; irangeMap.byKeyValue())
        ++countKV;

    assert(countKV == irangeMap.length);

    struct DtorLike {
    @nogc nothrow:
        int x;

        ~this() {
            printf("Called __dtor for %d\n", x);
            x = -1;
        }
    }

    Nogcaa!(int, DtorLike) dmap;
    scope (exit)
        dmap.free;

    foreach (i; 0 .. 128)
        dmap[i] = DtorLike(i);

    foreach (i; 0 .. 64)
        assert(dmap.remove(i));

    foreach (i; 64 .. 128)
        assert(dmap[i].x == i);

    Nogcaa!(int, int) empty;
    assert(!empty.length);
    assert(0 !in empty);
    assert(empty.get(5) == 0);

    foreach (kv; empty.byKeyValue())
        assert(0, "Shouldn't be here");

    Nogcaa!(int, int) growMap;
    scope (exit)
        growMap.free;

    foreach (i; 0 .. 4096)
        growMap[i] = i;
    assert(growMap.length == 4096);

    foreach (i; 0 .. 4090)
        growMap.remove(i);

    assert(growMap.length >= 1);

    printf("All additional tests passed. Final heap: %zu\n", Mallocator.instance.heap);
}
