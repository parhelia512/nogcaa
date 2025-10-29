module test;

import nogcaa;
import nogcsw;

static auto println(string format, Args...)(Args args) @nogc {
    import core.stdc.stdio;

    string fmt(string searchfor)() {
        char[] ctfeFmt = cast(char[])format;

        version (Windows)
            static foreach (i; 0 .. format.length - searchfor.length + 1)
                static if (format[i .. i + searchfor.length] == searchfor)
                    ctfeFmt[i .. i + searchfor.length] = "%lu";

        return cast(string)ctfeFmt ~ "\r\n";
    }

    return printf(mixin('"' ~ fmt!"%zu" ~ '"'), args);
}

extern (C) void main() @nogc {
    println!"Mallocator test";
    auto memory = Mallocator.allocate!int(1024);
    scope (exit) {
        Mallocator.instance.deallocate(memory);
        println!"Heap after deallocation: %zu"(Mallocator.instance.heap);
        assert(Mallocator.instance.heap == 0);
    }

    println!"Heap after allocation: %zu"(Mallocator.instance.heap);
    println!"[Array] length: %zu"(memory.length);
    println!"Pointer length: %zu"(Mallocator.length(memory.ptr));

    assert(memory.length == Mallocator.length(memory.ptr));

    auto sw = StopWatch(true);
    Nogcaa!(int, int) aa0;
    scope (exit) {
        aa0.free;
        println!"Elapsed time: %lf, heap after aa0.free: %zu"(
            cast(double)sw.elapsed!"usecs"() / 1_000_000, Mallocator.instance.heap);
    }

    foreach (i; 0 .. 1_000_000)
        aa0[i] = i;
    println!"Heap of aa0[%zu]: %zu"(aa0.length, Mallocator.instance.heap);

    foreach (i; 2_000 .. 1_000_000)
        aa0.remove(i);
    println!"aa0[1_000]: %d"(aa0[1_000]);

    println!"Elapsed time: %lf, heap: %zu"(
        cast(double)sw.elapsed!"usecs"() / 1_000_000, Mallocator
            .instance.heap);

    Nogcaa!(string, string) aa1;
    scope (exit) {
        println!"Heap before aa1.free(): %zu"(Mallocator.instance.heap);
        aa1.free;
        println!"After: %zu"(Mallocator.instance.heap);
    }

    aa1["Stevie"] = "Ray Vaughan";
    aa1["Asım Can"] = "Gündüz";
    aa1["Dan"] = "Patlansky";
    aa1["İlter"] = "Kurcala";
    aa1["Кириллица"] = "Тоже работает";
    aa1.Ferhat = "Kurtulmuş";

    foreach (pair; aa1)
        println!"%s -> %s"((*pair.pkey).ptr, (*pair.pvalue).ptr);

    if (auto pvalue = "Dan" in aa1)
        println!"Dan %s exists!"((*pvalue).ptr);
    else
        println!"Dan does not exist!";

    assert(aa1.remove("Ferhat") == true);
    assert(aa1["Ferhat"] == null);
    assert(aa1.remove("Foe") == false);
    assert(aa1["İlter"] == "Kurcala");

    aa1.rehash();

    println!"%s"(aa1["Stevie"].ptr);
    println!"%s"(aa1["Asım Can"].ptr);
    println!"%s"(aa1.Dan.ptr);
    println!"%s"(aa1["Ferhat"].ptr);

    auto keys = aa1.keys;
    scope (exit)
        Mallocator.instance.dispose(keys);
    foreach (key; keys)
        println!"%s -> %s"(key.ptr, aa1[key].ptr);

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

    println!"%s"(guitars[356].brand.ptr);

    if (auto valPtr = 3 in guitars)
        println!"%s"((*valPtr).brand.ptr);

    foreach (pairs; guitars.byKeyValue())
        println!"Guitar iter: %d, %s"(pairs.key, pairs.value.brand.ptr);

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
        println!"Heap before aas.free(): %zu"(Mallocator.instance.heap);
        aas.free;
        println!"After: %zu"(Mallocator.instance.heap);
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

    println!"Mallocator struct allocate test";
    auto p = Mallocator.allocate!Small();
    scope (exit) {
        Mallocator.instance.deallocate(p);
        println!"Mallocator heap after struct free: %zu"(Mallocator.instance.heap);
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

    println!"Array first: %d last: %d length: %zu"(arr[0], arr[$ - 1], arr.length);
    Mallocator.instance.deallocate(arr);

    Nogcaa!(int, int) map;
    scope (exit) {
        map.free;
        println!"map heap after free: %zu"(Mallocator.instance.heap);
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
        println!"Copied: %s, %s"(pairs.key.ptr, pairs.value.ptr);

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

    println!"All additional tests passed. Final heap: %zu"(Mallocator.instance.heap);
}
